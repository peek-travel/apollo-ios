import Foundation
#if !COCOAPODS
import Apollo
#endif
import SQLite

public final class SQLiteDotSwiftDatabase: SQLiteDatabase {

  private var db: Connection!
  
  private let records: Table
  private let keyColumn: SQLite.Expression<CacheKey>
  private let recordColumn: SQLite.Expression<String>

  private var lastReceivedAt = SQLite.Expression<Int64>("lastReceivedAt")
  private let version = SQLite.Expression<Int64>("version")
  
  public init(fileURL: URL) throws {
    self.records = Table(Self.tableName)
    self.keyColumn = SQLite.Expression<CacheKey>(Self.keyColumnName)
    self.recordColumn = SQLite.Expression<String>(Self.recordColumName)
    self.db = try Connection(.uri(fileURL.absoluteString), readonly: false)
  }
  
  public init(connection: Connection) {
    self.records = Table(Self.tableName)
    self.keyColumn = SQLite.Expression<CacheKey>(Self.keyColumnName)
    self.recordColumn = SQLite.Expression<String>(Self.recordColumName)
    self.db = connection
  }
  
  public func createRecordsTableIfNeeded() throws {
    try self.db.run(self.records.create(ifNotExists: true) { table in
      table.column(SQLite.Expression<Int64>(Self.idColumnName), primaryKey: .autoincrement)
      table.column(keyColumn, unique: true)
      table.column(SQLite.Expression<String>(Self.recordColumName))
    })
    try self.db.run(self.records.createIndex(keyColumn, unique: true, ifNotExists: true))
  }

  public func setUpDatabase() throws {
    try self.db.run(self.records.create(ifNotExists: true) { table in
      table.column(SQLite.Expression<Int64>(Self.idColumnName), primaryKey: .autoincrement)
      table.column(keyColumn, unique: true)
      table.column(SQLite.Expression<String>(Self.recordColumName))
    })
    try self.db.run(self.records.createIndex(SQLite.Expression<Int64>(Self.idColumnName), unique: true, ifNotExists: true))
    try self.runSchemaMigrationsIfNeeded()
  }

  
  public func selectRawRows(forKeys keys: Set<CacheKey>) throws -> [DatabaseRow] {
    let query = self.records.filter(keys.contains(keyColumn))
    return try self.db.prepareRowIterator(query).map { row in
      let record = row[self.recordColumn]
      let key = row[self.keyColumn]
      let lastReceivedAt = row[self.lastReceivedAt]
      
      return DatabaseRow(cacheKey: key, storedInfo: record, lastReceivedAt: lastReceivedAt)
    }
  }
  
  public func addOrUpdateRecordString(_ recordString: String, for cacheKey: CacheKey) throws {
    try self.db.run(self.records.insert(or: .replace, self.keyColumn <- cacheKey, self.recordColumn <- recordString))
  }
  
  public func deleteRecord(for cacheKey: CacheKey) throws {
    let query = self.records.filter(keyColumn == cacheKey)
    try self.db.run(query.delete())
  }

  public func deleteRecords(matching pattern: CacheKey) throws {
    let wildcardPattern = "%\(pattern)%"
    let query = self.records.filter(keyColumn.like(wildcardPattern))

    try self.db.run(query.delete())
  }
  
  public func clearDatabase(shouldVacuumOnClear: Bool) throws {
    try self.db.run(records.delete())
    if shouldVacuumOnClear {
      try self.db.prepare("VACUUM;").run()
    }
  }

  /// Returns the version of the database schema.
  public func readSchemaVersion() throws -> Int64? {
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
      try self.db.run(self.records.addColumn(self.lastReceivedAt, defaultValue: 0))
    }

    try self.db.run("PRAGMA user_version = \(Self.schemaVersion);")
  }

  public func insert(_ key: CacheKey, row: Apollo.RecordRow?, serializedRecord: String) throws {
    let lastReceivedAt: Int64
    if let row = row {
      lastReceivedAt = Int64(row.lastReceivedAt.timeIntervalSince1970)
    }
    else {
      lastReceivedAt = Int64(Date().timeIntervalSince1970)
    }
    try self.db.run(self.records.insert(
      or: .replace,
      self.keyColumn <- key,
      SQLite.Expression<String>(Self.recordColumName) <- serializedRecord,
      self.lastReceivedAt <- lastReceivedAt
    ))
  }

}

extension SQLiteDotSwiftDatabase {
  private static var schemaVersion: Int64 { 1 } 
}
