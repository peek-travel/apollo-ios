import ApolloAPI
import Foundation

final class GraphQLFirstReceivedAtTracker: GraphQLResultAccumulator {
  var requiresCacheKeyComputation: Bool { false }

  /*
    This accumulator uses max and distantPast for comparisons of the first received date.

    The primary purpose of the date is the *oldest* age of data in a given object graph.

    It is responsible for providing a default value when dealing with data for the first time, so `oldestDate` is used.

    However, once a date has been established it needs to compare against the previous age established - which is `distantPast`.

    So we compare dates using `max()`.
    */
  

  func accept(childObject: Date, info: FieldExecutionInfo) throws -> Date {
    return childObject
  }

  func accept(scalar: JSONValue, firstReceivedAt: Date, info: FieldExecutionInfo) throws -> Date {
    return firstReceivedAt
  }

  func accept(customScalar: JSONValue, firstReceivedAt: Date, info: FieldExecutionInfo) throws -> Date {
    return firstReceivedAt
  }

  func acceptNullValue(firstReceivedAt: Date, info: FieldExecutionInfo) throws -> Date {
    return firstReceivedAt
  }

  func acceptMissingValue(firstReceivedAt: Date, info: FieldExecutionInfo) throws -> Date {
    return firstReceivedAt
  }

  func accept(list: [Date], info: FieldExecutionInfo) throws -> Date {
    return list.map { $0 }.max() ?? .distantPast
  }

  func accept(fieldEntry: Date, info: FieldExecutionInfo) throws -> Date? {
    return fieldEntry
  }

  func accept(fieldEntries: [Date], info: ObjectExecutionInfo) throws -> Date {
    return fieldEntries.max() ?? .distantPast
  }

  func finish(rootValue: Date, info: ObjectExecutionInfo) throws -> GraphQLResultMetadata {
    return GraphQLResultMetadata(maxAge: rootValue)
  }

}
