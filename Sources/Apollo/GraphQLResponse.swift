#if !COCOAPODS
import ApolloAPI
#endif

import Foundation

/// Represents a complete GraphQL response received from a server.
public final class GraphQLResponse<Data: RootSelectionSet> {
  private let base: AnyGraphQLResponse

  public init<Operation: GraphQLOperation>(
    operation: Operation,
    body: JSONObject
  ) where Operation.Data == Data {
    self.base = AnyGraphQLResponse(
      body: body,
      rootKey: CacheReference.rootCacheReference(for: Operation.operationType),
      variables: operation.__variables
    )
  }

  /// Parses the response into a `GraphQLResult` and a `RecordSet` depending on the cache policy. The result can be
  /// sent to a completion block for a request and the `RecordSet` can be merged into a local cache.
  ///
  /// - Returns: A tuple of a `GraphQLResult` and an optional `RecordSet`.
  /// 
  /// - Parameter cachePolicy: Used to determine whether a cache `RecordSet` is returned. A cache policy that does
  /// not read or write to the cache will return a `nil` cache `RecordSet`.
  public func parseResult(withCachePolicy cachePolicy: CachePolicy) throws -> (GraphQLResult<Data>, RecordSet?) {
    switch cachePolicy {
    case .fetchIgnoringCacheCompletely:
      // There is no cache, so we don't need to get any info on dependencies. Use fast parsing.
      return (try parseResultFast(), nil)

    default:
      return try parseResult()
    }
  }

  /// Parses a response into a `GraphQLResult` and a `RecordSet`. The result can be sent to a completion block for a 
  /// request and the `RecordSet` can be merged into a local cache.
  ///
  /// - Returns: A `GraphQLResult` and a `RecordSet`.
  public func parseResult() throws -> (GraphQLResult<Data>, RecordSet?) {
    let accumulator = zip(
      GraphQLSelectionSetMapper<Data>(),
      ResultNormalizerFactory.networkResponseDataNormalizer(),
      GraphQLDependencyTracker(),
      GraphQLFirstReceivedAtTracker()
    )
    let executionResult = try base.execute(
      selectionSet: Data.self,
      with: accumulator
    )
    let result = makeResult(data: executionResult?.0, dependentKeys: executionResult?.2, resultContext: executionResult?.3 ?? GraphQLResultMetadata())

    return (result, executionResult?.1)
  }

  private func execute<Accumulator: GraphQLResultAccumulator>(
    with accumulator: Accumulator
  ) throws -> Accumulator.FinalResult? {
    guard let dataEntry = body["data"] as? JSONObject else {
      return nil
    }

    let executor = GraphQLExecutor(executionSource: NetworkResponseExecutionSource())

    return try executor.execute(selectionSet: Data.self,
                                on: dataEntry,
                                firstReceivedAt: Date(),
                                withRootCacheReference: rootKey,
                                variables: variables,
                                accumulator: accumulator)
  }

  private func makeResult(data: Data?, dependentKeys: Set<CacheKey>?, resultContext: GraphQLResultMetadata) -> GraphQLResult<Data> {
    let errors = self.parseErrors()
    let extensions = body["extensions"] as? JSONObject

    return GraphQLResult(data: data,
                         extensions: extensions,
                         errors: errors,
                         source: .server,
                         dependentKeys: dependentKeys,
                         metadata: resultContext)
  }

  private func parseErrors() -> [GraphQLError]? {
    guard let errorsEntry = self.body["errors"] as? [JSONObject] else {
      return nil
    }

    return errorsEntry.map(GraphQLError.init)
  }

  /// Parses a response into a `GraphQLResult` for use without the cache. This parsing does not
  /// create dependent keys or a `RecordSet` for the cache.
  ///
  /// This is faster than `parseResult()` and should be used when cache the response is not needed.
  public func parseResultFast() throws -> GraphQLResult<Data>  {
    let accumulator = GraphQLSelectionSetMapper<Data>()
    let data = try execute(selectionSet: Data.self, with: accumulator)
    return makeResult(data: data, dependentKeys: nil, resultContext: GraphQLResultMetadata())
  }

  private func makeResult(data: Data?, dependentKeys: Set<CacheKey>?) -> GraphQLResult<Data> {
    return GraphQLResult(
      data: data,
      extensions: base.parseExtensions(),
      errors: base.parseErrors(),
      source: .server,
      dependentKeys: dependentKeys
    )
  }
}

// MARK: - Equatable Conformance

extension GraphQLResponse: Equatable where Data: Equatable {
  public static func == (lhs: GraphQLResponse<Data>, rhs: GraphQLResponse<Data>) -> Bool {
    lhs.base == rhs.base
  }
}

// MARK: - Hashable Conformance

extension GraphQLResponse: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(base)
  }
}
