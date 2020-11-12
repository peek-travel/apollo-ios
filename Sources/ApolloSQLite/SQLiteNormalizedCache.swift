import Foundation
import SQLite
#if !COCOAPODS
import Apollo
#endif

public enum SQLiteNormalizedCacheError: Error {
  case invalidRecordEncoding(record: String)
  case invalidRecordShape(object: Any)
}

/// A `NormalizedCache` implementation which uses a SQLite database to store data.
public final class SQLiteNormalizedCache {

  private let db: Connection
  private let records = Table("records")
  private let id = Expression<Int64>("_id")
  private let key = Expression<CacheKey>("key")
  private let record = Expression<String>("record")
  private let lastReceivedAt = Expression<Int64>("lastReceivedAt")
  private let version = Expression<Int64>("version")
  private let shouldVacuumOnClear: Bool

  /// Creates a store that uses the provided SQLite file connection.
  /// - Parameters:
  ///   - db: The database connection to use.
  ///   - shouldVacuumOnClear: If the database file should compact "VACUUM" its storage when clearing records. This can be a potentially long operation.
  ///   Default is `false`. This SHOULD be set to `true` if you are storing any Personally Identifiable Information in the cache.
  ///   - initialRecords: A set of records to initialize the database with.
  /// - Throws: Any errors attempting to access the database.
  public init(db: Connection, compactFileOnClear shouldVacuumOnClear: Bool = false, initialRecords: RecordSet? = nil) throws {
    self.shouldVacuumOnClear = shouldVacuumOnClear
    self.db = db
    try self.setUpDatabase()

    guard let initialRecords = initialRecords else { return }

    try initialRecords.keys.forEach { key in
      guard let row = initialRecords[key] else {
        assertionFailure("No record was found for the existing key")
        return
      }
      guard let serializedRecord = try row.record.serialized() else { return }
      try self.db.run(self.records.insert(
        or: .replace,
        self.key <- key,
        self.record <- serializedRecord,
        self.lastReceivedAt <- Int64(row.lastReceivedAt.timeIntervalSince1970)
      ))
    }
  }

  /// Creates a store that will establish its own connection to the SQLite file at the provided url.
  /// - Parameters:
  ///   - fileURL: The file URL to use for your database.
  ///   - shouldVacuumOnClear: If the database file should compact "VACUUM" its storage when clearing records. This can be a potentially long operation.
  ///   Default is `false`. This SHOULD be set to `true` if you are storing any Personally Identifiable Information in the cache.
  ///   - initialRecords: A set of records to initialize the database with.
  /// - Throws: Any errors attempting to open or create the database.
  convenience public init(
    fileURL: URL,
    compactFileOnClear shouldVacuumOnClear: Bool = false,
    initialRecords: RecordSet? = nil
  ) throws {
    try self.init(
      db: try Connection(.uri(fileURL.absoluteString), readonly: false),
      compactFileOnClear: shouldVacuumOnClear,
      initialRecords: initialRecords
    )
  }

  private func recordCacheKey(forFieldCacheKey fieldCacheKey: CacheKey) -> CacheKey {
    let components = fieldCacheKey.components(separatedBy: ".")
    var updatedComponents = [String]()
    if components.first?.contains("_ROOT") == true {
      for component in components {
        if updatedComponents.last?.last?.isNumber ?? false && component.first?.isNumber ?? false {
          updatedComponents[updatedComponents.count - 1].append(".\(component)")
        } else {
          updatedComponents.append(component)
        }
      }
    } else {
      updatedComponents = components
    }

    if updatedComponents.count > 1 {
      updatedComponents.removeLast()
    }
    return updatedComponents.joined(separator: ".")
  }

  private func setUpDatabase() throws {

    try self.db.run(self.records.create(ifNotExists: true) { table in
      table.column(id, primaryKey: .autoincrement)
      table.column(key, unique: true)
      table.column(record)
    })
    try self.db.run(self.records.createIndex(key, unique: true, ifNotExists: true))
    try self.runSchemaMigrationsIfNeeded()
  }

  private func mergeRecords(records: RecordSet) throws -> Set<CacheKey> {
    var recordSet = RecordSet(rows: try self.selectRows(forKeys: records.keys))
    let changedFieldKeys = Set(recordSet.merge(records: records))
    let changedRecordKeys = Set(changedFieldKeys.map { self.recordCacheKey(forFieldCacheKey: $0) })

    try changedRecordKeys.forEach { recordKey in
      guard let serializedRecord = try recordSet[recordKey]?.record.serialized() else { return }

      try self.db.run(self.records.insert(
        or: .replace,
        self.key <- recordKey,
        self.record <- serializedRecord,
        self.lastReceivedAt <- Int64(Date().timeIntervalSince1970)
      ))
    }

    return changedFieldKeys
  }

  private func selectRows(forKeys keys: [CacheKey]) throws -> [RecordRow] {
    let query = self.records.filter(keys.contains(key))
    return try self.db.prepare(query).map { try parse(row: $0) }
  }

  private func clearRecords(accordingTo policy: CacheClearingPolicy) throws {
    switch policy._value {
    case let .first(count):
      let firstKRecords = records.select(self.id).order(self.id.asc).limit(count)
      try self.db.run(firstKRecords.delete())

    case let .last(count):
      let lastKRecords = records.select(self.id).order(self.id.desc).limit(count)
      try self.db.run(lastKRecords.delete())

    case let .allMatchingKeyPattern(pattern):
      let matchingRecords = records.where(
        self.key.like(pattern.replacingOccurrences(of: "*", with: "%"))
      )
      try self.db.run(matchingRecords.delete())

    case let .everythingBefore(date):
      let oldRecords = records.where(
        self.lastReceivedAt < Int64(date.timeIntervalSince1970)
      )
      try self.db.run(oldRecords.delete())

    case .allRecords: fallthrough
    default:
      try self.db.run(records.delete())
    }

    guard self.shouldVacuumOnClear else { return }

    try self.db.prepare("VACUUM;").run()
  }

  private func parse(row: Row) throws -> RecordRow {
    let record = row[self.record]

    guard let recordData = record.data(using: .utf8) else {
      throw SQLiteNormalizedCacheError.invalidRecordEncoding(record: record)
    }

    let fields = try SQLiteSerialization.deserialize(data: recordData)
    return RecordRow(
      record: Record(key: row[key], fields),
      lastReceivedAt: Date(timeIntervalSince1970: TimeInterval(row[self.lastReceivedAt]))
    )
  }
}

// MARK: - Schema migrations

extension SQLiteNormalizedCache {
  private static var schemaVersion: Int64 { 1 }

  /// Returns the version of the database schema.
  func readSchemaVersion() throws -> Int64? {
    for record in try db.prepare("PRAGMA user_version") {
      if let value = record[0] as? Int64 {
        return value
      }
    }
    return nil
  }

  private func runSchemaMigrationsIfNeeded() throws {
    let currentVersion = try self.readSchemaVersion() ?? -1

    // if the currentVersion the same as our schema version then no migrations are necessary
    guard currentVersion < Self.schemaVersion else { return }

    if currentVersion < 1 {
        try self.db.run(self.records.addColumn(lastReceivedAt, defaultValue: 0))
    }

    try self.db.run("PRAGMA user_version = \(Self.schemaVersion);")
  }
}

// MARK: - NormalizedCache conformance

extension SQLiteNormalizedCache: NormalizedCache {

  public func merge(records: RecordSet,
                    callbackQueue: DispatchQueue?,
                    completion: @escaping (Swift.Result<Set<CacheKey>, Error>) -> Void) {
    let result: Swift.Result<Set<CacheKey>, Error>
    do {
      let records = try self.mergeRecords(records: records)
      result = .success(records)
    } catch {
      result = .failure(error)
    }

    DispatchQueue.apollo.returnResultAsyncIfNeeded(on: callbackQueue,
                                                   action: completion,
                                                   result: result)
  }

  public func loadRecords(forKeys keys: [CacheKey],
                          callbackQueue: DispatchQueue?,
                          completion: @escaping (Swift.Result<[RecordRow?], Error>) -> Void) {
    let result: Swift.Result<[RecordRow?], Error>
    do {
      let rows = try self.selectRows(forKeys: keys)
      result = .success(
        keys.map { key in
          guard let recordIndex = rows.firstIndex(where: { $0.record.key == key }) else { return nil }
          return rows[recordIndex]
        }
      )
    } catch {
      result = .failure(error)
    }

    DispatchQueue.apollo.returnResultAsyncIfNeeded(on: callbackQueue,
                                                   action: completion,
                                                   result: result)
  }

  public func clear(
    _ clearingPolicy: CacheClearingPolicy,
    callbackQueue: DispatchQueue?,
    completion: ((Swift.Result<Void, Error>) -> Void)?
  ) {
    let result: Swift.Result<Void, Error>
    do {
      try self.clearRecords(accordingTo: clearingPolicy)
      result = .success(())
    } catch {
      result = .failure(error)
    }

    DispatchQueue.apollo.returnResultAsyncIfNeeded(on: callbackQueue,
                                                   action: completion,
                                                   result: result)
  }

  public func clearImmediately(_ clearingPolicy: CacheClearingPolicy) throws {
    try self.clearRecords(accordingTo: clearingPolicy)
  }
}

// MARK: Record serialization

extension Record {
  func serialized() throws -> String? {
    let serializedData = try SQLiteSerialization.serialize(fields: self.fields)
    guard let string = String(data: serializedData, encoding: .utf8) else {
      assertionFailure("Serialization should yield UTF-8 data")
      return nil
    }
    return string
  }
}
