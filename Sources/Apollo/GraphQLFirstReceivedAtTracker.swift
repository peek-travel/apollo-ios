import Foundation

/*
 This accumulator uses max and distantPast for comparisons of the first received date.

 The primary purpose of the date is the *oldest* age of data in a given object graph.

 It is responsible for providing a default value when dealing with data for the first time, so `oldestDate` is used.

 However, once a date has been established it needs to compare against the previous age established - which is `distantPast`.

 So we compare dates using `max()`.
 */

final class GraphQLFirstReceivedAtTracker: GraphQLResultAccumulator {
  func accept(scalar: JSONValue, firstReceivedAt: Date, info: GraphQLResolveInfo) throws -> Date? {
    return firstReceivedAt
  }

  func acceptNullValue(firstReceivedAt: Date, info: GraphQLResolveInfo) throws -> Date? {
    return firstReceivedAt
  }

  func accept(list: [Date?], info: GraphQLResolveInfo) throws -> Date? {
    return list.compactMap({ $0 }).max()
  }

  func accept(fieldEntry: Date?, info: GraphQLResolveInfo) throws -> Date {
    return fieldEntry ?? .distantPast
  }

  func accept(fieldEntries: [Date], info: GraphQLResolveInfo) throws -> Date {
    return fieldEntries.max() ?? .distantPast
  }

  func finish(rootValue: Date, info: GraphQLResolveInfo) throws -> GraphQLResultMetadata {
    return GraphQLResultMetadata(maxAge: rootValue)
  }
}
