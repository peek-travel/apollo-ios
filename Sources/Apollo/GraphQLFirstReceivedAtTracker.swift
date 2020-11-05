import struct Foundation.Date

final class GraphQLFirstReceivedAtTracker: GraphQLResultAccumulator {
  func accept(scalar: JSONValue, firstReceivedAt: Date, info: GraphQLResolveInfo) throws -> Date {
    return firstReceivedAt
  }

  func acceptNullValue(firstReceivedAt: Date, info: GraphQLResolveInfo) throws -> Date {
    return firstReceivedAt
  }

  func accept(list: [Date], info: GraphQLResolveInfo) throws -> Date {
    return list.min() ?? Date(timeIntervalSince1970: 0)
  }

  func accept(fieldEntry: Date, info: GraphQLResolveInfo) throws -> Date {
    return fieldEntry
  }

  func accept(fieldEntries: [Date], info: GraphQLResolveInfo) throws -> Date {
    return fieldEntries.min() ?? Date(timeIntervalSince1970: 0)
  }

  func finish(rootValue: Date, info: GraphQLResolveInfo) throws -> GraphQLResultContext {
    return .init(resultAge: rootValue)
  }
}
