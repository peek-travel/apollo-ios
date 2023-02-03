import Foundation

/// A row of data that contains a `Record` and some associated metadata.
public struct RecordRow: Hashable {
   public internal(set) var record: Record
   public internal(set) var lastReceivedAt: Date

   public init(record: Record, lastReceivedAt: Date) {
     self.record = record
     self.lastReceivedAt = lastReceivedAt
   }
  public func hash(into hasher: inout Hasher) {
    hasher.combine(self.record)
  }
 }

/// A set of cache records.
public struct RecordSet: Hashable {
  public private(set) var storage: [CacheKey: RecordRow] = [:]

  public init<S: Sequence>(rows: S) where S.Iterator.Element == RecordRow {
    self.insert(contentsOf: rows)
  }

  public mutating func insert(_ row: RecordRow) {
    self.storage[row.record.key] = row
  }
  
  public mutating func removeRecord(for key: CacheKey) {
    storage.removeValue(forKey: key)
  }

  public mutating func removeRecords(matching pattern: CacheKey) {
    for (key, _) in storage {
      if key.range(of: pattern, options: .caseInsensitive) != nil {
        storage.removeValue(forKey: key)
      }
    }
  }

  public mutating func clear() {
    storage.removeAll()
  }

  public mutating func insert<S: Sequence>(contentsOf rows: S) where S.Iterator.Element == RecordRow {
    rows.forEach { self.insert($0) }
  }

  public subscript(key: CacheKey) -> RecordRow? {
    return self.storage[key]
  }

  public var isEmpty: Bool {
    return storage.isEmpty
  }

  public var keys: Set<CacheKey> {
    return Set(storage.keys)
  }

  @discardableResult public mutating func merge(records: RecordSet) -> Set<CacheKey> {
    return records.storage.reduce(into: []) { result, next in
      result.formUnion(merge(record: next.value.record, lastReceivedAt: next.value.lastReceivedAt))
    }
  }

  @discardableResult public mutating func merge(record: Record, lastReceivedAt: Date) -> Set<CacheKey> {
    guard var oldRow = storage.removeValue(forKey: record.key) else {
      storage[record.key] = .init(record: record, lastReceivedAt: lastReceivedAt)
      return Set(record.fields.keys.map({ [record.key, $0].joined(separator: ".") }))
    }

    var changedKeys: Set<CacheKey> = []
    changedKeys.reserveCapacity(record.fields.count)

    for (key, value) in record.fields {
      if let oldValue = oldRow.record.fields[key], oldValue == value {
        continue
      }
      oldRow.record[key] = value
      oldRow.lastReceivedAt = Date()
      changedKeys.insert([record.key, key].joined(separator: "."))
    }
    storage[record.key] = oldRow
    return changedKeys
  }
}

extension RecordSet: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (CacheKey, Record.Fields)...) {
    self.init(rows: elements.map { element in
       RecordRow(
         record: Record(key: element.0, element.1),
         lastReceivedAt: Date()
       )
     })
  }
}

extension RecordSet: CustomStringConvertible {
  public var description: String {
    return String(describing: Array(storage.values))
  }
}

extension RecordSet: CustomDebugStringConvertible {
  public var debugDescription: String {
    return description
  }
}

extension RecordSet: CustomPlaygroundDisplayConvertible {
  public var playgroundDescription: Any {
    return description
  }
}
