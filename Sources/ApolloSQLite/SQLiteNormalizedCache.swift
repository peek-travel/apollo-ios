import Foundation
#if !COCOAPODS
import Apollo
#endif

public enum SQLiteNormalizedCacheError: Error {
  case invalidRecordEncoding(record: String)
  case invalidRecordShape(object: Any)
}

/// A `NormalizedCache` implementation which uses a SQLite database to store data.
public final class SQLiteNormalizedCache {

  private let shouldVacuumOnClear: Bool
  
  let database: any SQLiteDatabase

  /// Designated initializer
  ///
  /// - Parameters:
  ///   - fileURL: The file URL to use for your database.
  ///   - shouldVacuumOnClear: If the database should also be `VACCUM`ed on clear to remove all traces of info. Defaults to `false` since this involves a performance hit, but this should be used if you are storing any Personally Identifiable Information in the cache.
  ///   - initialRecords: A set of records to initialize the database with.
  /// - Throws: Any errors attempting to open or create the database.
<<<<<<< HEAD

  convenience public init(fileURL: URL, databaseType: SQLiteDatabase.Type = SQLiteDotSwiftDatabase.self, shouldVacuumOnClear: Bool = false, initialRecords: RecordSet? = nil) throws {
    try self.init(database: databaseType.init(fileURL: fileURL),
                  shouldVacuumOnClear: shouldVacuumOnClear,
                  initialRecords: initialRecords
    )
  }

  public init(database: SQLiteDatabase,
              shouldVacuumOnClear: Bool = false, initialRecords: RecordSet? = nil) throws {
=======
  public init(fileURL: URL,
              databaseType: any SQLiteDatabase.Type = SQLiteDotSwiftDatabase.self,
              shouldVacuumOnClear: Bool = false) throws {
    self.database = try databaseType.init(fileURL: fileURL)
    self.shouldVacuumOnClear = shouldVacuumOnClear
    try self.database.createRecordsTableIfNeeded()
  }

  public init(database: any SQLiteDatabase,
              shouldVacuumOnClear: Bool = false) throws {
>>>>>>> tags/1.15.2
    self.database = database
    self.shouldVacuumOnClear = shouldVacuumOnClear
    try self.database.setUpDatabase()

    guard let initialRecords = initialRecords else { return }

    try initialRecords.keys.forEach { key in
      guard let row = initialRecords[key] else {
        assertionFailure("No record was found for the existing key")
        return
      }
      guard let serializedRecord = try row.record.serialized() else { return }
      try self.database.insert(key, row: row, serializedRecord: serializedRecord)
    }

  }
  
  private func recordCacheKey(forFieldCacheKey fieldCacheKey: CacheKey) -> CacheKey {
    let components = fieldCacheKey.splitIntoCacheKeyComponents()
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

  private func mergeRecords(records: RecordSet) throws -> Set<CacheKey> {
    var recordSet = RecordSet(rows: try self.selectRows(for: records.keys))
    let changedFieldKeys = recordSet.merge(records: records)
    let changedRecordKeys = changedFieldKeys.map { self.recordCacheKey(forFieldCacheKey: $0) }
<<<<<<< HEAD
    try changedRecordKeys.forEach { recordKey in
      guard let serializedRecord = try recordSet[recordKey]?.record.serialized() else { return }
      try self.database.insert(recordKey, row: recordSet[recordKey], serializedRecord: serializedRecord)
    }

    return changedFieldKeys
=======

    let serializedRecords = try Set(changedRecordKeys)
      .compactMap { recordKey -> (CacheKey, String)? in
        if let recordFields = recordSet[recordKey]?.fields {
          let recordData = try SQLiteSerialization.serialize(fields: recordFields)
          guard let recordString = String(data: recordData, encoding: .utf8) else {
            assertionFailure("Serialization should yield UTF-8 data")
            return nil
          }
          return (recordKey, recordString)
        }
        return nil
      }

    try self.database.addOrUpdate(records: serializedRecords)
    return Set(changedFieldKeys)
>>>>>>> tags/1.15.2
  }
  
  fileprivate func selectRows(for keys: Set<CacheKey>) throws -> [RecordRow] {
    try self.database.selectRawRows(forKeys: keys)
      .map { try self.parse(row: $0) }
  }

  private func parse(row: DatabaseRow) throws -> RecordRow {
    guard let recordData = row.storedInfo.data(using: .utf8) else {
      throw SQLiteNormalizedCacheError.invalidRecordEncoding(record: row.storedInfo)
    }

    let fields = try SQLiteSerialization.deserialize(data: recordData)
    return RecordRow(record: Record(key: row.cacheKey, fields), lastReceivedAt: Date(timeIntervalSince1970: TimeInterval(row.lastReceivedAt)))
  }
}

// MARK: - NormalizedCache conformance

extension SQLiteNormalizedCache: NormalizedCache {
  public func loadRecords(forKeys keys: Set<CacheKey>) throws -> [CacheKey: RecordRow] {
    return [CacheKey: RecordRow](uniqueKeysWithValues:
                                try selectRows(for: keys)
                                .map { row in
                                  (row.record.key, row)
                                })
  }
  
  public func merge(records: RecordSet) throws -> Set<CacheKey> {
    return try mergeRecords(records: records)
  }
  
  public func removeRecord(for key: CacheKey) throws {
    try self.database.deleteRecord(for: key)
  }

  public func removeRecords(matching pattern: CacheKey) throws {
    try self.database.deleteRecords(matching: pattern)
  }
  
  public func clear() throws {
    try self.database.clearDatabase(shouldVacuumOnClear: self.shouldVacuumOnClear)
  }
}

extension String {
  private var isBalanced: Bool {
    guard contains("(") || contains(")") else { return true }

    var stack = [Character]()
    for character in self where ["(", ")"].contains(character) {
      if character == "(" {
        stack.append(character)
      } else if !stack.isEmpty && character == ")" {
        _ = stack.popLast()
      }
    }

    return stack.isEmpty
  }

  func splitIntoCacheKeyComponents() -> [String] {
    var result = [String]()
    var unbalancedString = ""
    let tmp = split(separator: ".", omittingEmptySubsequences: false)
    tmp
      .enumerated()
      .forEach { index, item in
        let value = String(item)
        if value.isBalanced && unbalancedString == "" {
          result.append(value)
        } else {
          unbalancedString += unbalancedString == "" ? value : ".\(value)"
          if unbalancedString.isBalanced {
            result.append(unbalancedString)
            unbalancedString = ""
          }
        }
        if unbalancedString != "" && index == tmp.count - 1 {
          result.append(unbalancedString)
        }
      }
    return result
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
