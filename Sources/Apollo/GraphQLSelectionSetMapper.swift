#if !COCOAPODS
import ApolloAPI
#endif
import Foundation

/// An accumulator that maps executed data to create a `SelectionSet`.
@_spi(Execution)
public final class GraphQLSelectionSetMapper<T: SelectionSet>: GraphQLResultAccumulator {

  let dataDictMapper: DataDictMapper

  public init(dataDictMapper: DataDictMapper) {
    self.dataDictMapper = dataDictMapper
  }

  public var requiresCacheKeyComputation: Bool {
    dataDictMapper.requiresCacheKeyComputation
  }

  public var handleMissingValues: DataDictMapper.HandleMissingValues {
    dataDictMapper.handleMissingValues
  }

  func accept(scalar: AnyHashable, firstReceivedAt: Date,  info: FieldExecutionInfo) throws -> AnyHashable? {
    switch info.field.type.namedType {
    case let .scalar(decodable as any JSONDecodable.Type):
      // This will convert a JSON value to the expected value type.
      return try decodable.init(_jsonValue: scalar)._asAnyHashable
    default:
      preconditionFailure()
    }
  }

  func accept(customScalar: AnyHashable, firstReceivedAt: Date, info: FieldExecutionInfo) throws -> AnyHashable? {
    switch info.field.type.namedType {
    case let .customScalar(decodable as any JSONDecodable.Type):
      // This will convert a JSON value to the expected value type,
      // which could be a custom scalar or an enum.
      return try decodable.init(_jsonValue: customScalar)._asAnyHashable
    default:
      preconditionFailure()
    }
  }

  func acceptNullValue(firstReceivedAt: Date, info: FieldExecutionInfo) -> AnyHashable? {
    return DataDict._NullValue
  }

  func acceptMissingValue(firstReceivedAt: Date, info: FieldExecutionInfo) throws -> AnyHashable? {
    switch handleMissingValues {
    case .allowForOptionalFields where info.field.type.isNullable: fallthrough
    case .allowForAllFields:
      return nil

    default:
      throw JSONDecodingError.missingValue
    }
  }

  public func accept(list: [AnyHashable?], info: FieldExecutionInfo) -> AnyHashable? {
    return list
  }

  public func accept(childObject: DataDict, info: FieldExecutionInfo) throws -> AnyHashable? {
    return childObject
  }

  public func accept(fieldEntry: AnyHashable?, info: FieldExecutionInfo) -> (key: String, value: AnyHashable)? {
    guard let fieldEntry = fieldEntry else { return nil }
    return (info.responseKeyForField, fieldEntry)
  }

  public func accept(
    fieldEntries: [(key: String, value: AnyHashable)],
    info: ObjectExecutionInfo
  ) throws -> DataDict {
    return DataDict(
      data: .init(fieldEntries, uniquingKeysWith: { (_, last) in last }),
      fulfilledFragments: info.fulfilledFragments,
      deferredFragments: info.deferredFragments
    )
  }

  public func finish(rootValue: DataDict, info: ObjectExecutionInfo) -> T {
    return T.init(_dataDict: rootValue)
  }
}
