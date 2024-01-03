@testable import Apollo
import ApolloAPI
import XCTest

final class CacheTests: XCTestCase, CacheDependentTesting, StoreLoading {
  var cacheType: TestCacheProvider.Type {
    InMemoryTestCacheProvider.self
  }

  static let defaultWaitTimeout: TimeInterval = 5.0

  var cache: Apollo.NormalizedCache!
  var server: MockGraphQLServer!
  var store: ApolloStore!
  var client: ApolloClient!

  override func setUpWithError() throws {
    try super.setUpWithError()

    cache = try makeNormalizedCache()
    store = ApolloStore(cache: cache)

    server = MockGraphQLServer()
    let networkTransport = MockNetworkTransport(server: server, store: store)
    client = ApolloClient(networkTransport: networkTransport, store: store)
  }

  override func tearDownWithError() throws {
    cache = nil
    store = nil
    server = nil
    client = nil

    try super.tearDownWithError()
  }

  func testFetchReturningCacheDataOnErrorReturnsData() throws {
    class HeroNameSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self)
        ]}
      }
    }

    let query = MockQuery<HeroNameSelectionSet>()

    mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": [
        "name": "R2-D2",
        "__typename": "Droid"
      ]
    ])

    let serverRequestExpectation =
      server.expect(MockQuery<HeroNameSelectionSet>.self) { request in
      [
        "data": [
          "hero": [:] as JSONObject // incomplete data will cause an error on fetch
        ]
      ]
    }

    let resultObserver = makeResultObserver(for: query)

    let fetchResultFromServerExpectation = resultObserver.expectation(description: "Received result from cache") { result in
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)

        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "R2-D2")
      }
    }

    client.fetch(query: query, cachePolicy: .fetchReturningCacheDataOnError, resultHandler: resultObserver.handler)

    wait(for: [serverRequestExpectation, fetchResultFromServerExpectation], timeout: Self.defaultWaitTimeout)
  }

  func testResultContextWithDataFromYesterday() throws {
    let now = Date()
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
    let aYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: now)!

    let initialRecords = RecordSet([
      "QUERY_ROOT": (["hero": CacheReference("hero")], yesterday),
      "hero": (["__typename": "Droid", "name": "R2-D2"], yesterday),
      "ignoredData": (["__typename": "Droid", "name": "R2-D3"], aYearAgo)
    ])
    try self.testResulContextWhenLoadingHeroNameQueryWithAge(initialRecords: initialRecords, expectedResultAge: yesterday)
  }

  func testResultContextWithDataFromMixedDates() throws {
    let now = Date()
    let oneHourAgo = Calendar.current.date(byAdding: .hour, value: -1, to: now)!
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
    let aYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: now)!


    let fields = (
      ["hero": CacheReference("hero")],
      ["__typename": "Droid", "name": "R2-D2"],
      ["__typename": "Droid", "name": "R2-D3"]
    )

    let initialRecords1 = RecordSet([
      "QUERY_ROOT": (fields.0, yesterday),
      "hero": (fields.1, yesterday),
      "ignoredData": (fields.2, aYearAgo)
    ])


    try self.testResulContextWhenLoadingHeroNameQueryWithAge(initialRecords: initialRecords1, expectedResultAge: yesterday)

    let initialRecords2 = RecordSet([
      "QUERY_ROOT": (fields.0, yesterday),
      "hero": (fields.1, oneHourAgo),
      "ignoredData": (fields.2, aYearAgo)
    ])

    try self.testResulContextWhenLoadingHeroNameQueryWithAge(initialRecords: initialRecords2, expectedResultAge: yesterday)
  }
  
  func testReceivedAtAfterUpdateQuery() throws {
    // given
    struct GivenSelectionSet: MockMutableRootSelectionSet {
      public var __data: DataDict = .empty()
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}

      var hero: Hero {
        get { __data["hero"] }
        set { __data["hero"] = newValue }
      }

      struct Hero: MockMutableRootSelectionSet {
        public var __data: DataDict = .empty()
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __selections: [Selection] { [
          .field("name", String.self)
        ]}

        var name: String {
          get { __data["name"] }
          set { __data["name"] = newValue }
        }
      }
    }

    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    let initialRecords = RecordSet([
      "QUERY_ROOT": (["hero": CacheReference("QUERY_ROOT.hero")], yesterday),
      "QUERY_ROOT.hero": (["__typename": "Droid", "name": "R2-D2"], yesterday)
    ])
    let cacheMutation = MockLocalCacheMutation<GivenSelectionSet>()
    mergeRecordsIntoCache(initialRecords)

    runActivity("update mutation") { _ in

      let expectation = self.expectation(description: "transaction'd")
      store.withinReadWriteTransaction({ transaction in
        try transaction.update(cacheMutation) { data in
          data.hero.name = "Artoo"
        }
      }, completion: { result in
        defer { expectation.fulfill() }
        XCTAssertSuccessResult(result)
      })
      self.wait(for: [expectation], timeout: Self.defaultWaitTimeout)

      let query = MockQuery<GivenSelectionSet>()
      loadFromStore(operation: query) { result in
        switch result {
        case let .success(success):
          // the query age is that of the oldest row read, so still yesterday
          XCTAssertEqual(
            Calendar.current.compare(yesterday, to: success.metadata.maxAge, toGranularity: .minute),
            .orderedSame
          )
        case let .failure(error):
          XCTFail("Unexpected error: \(error)")
        }

      }
    }

    runActivity("read object") { _ in
      // verify that the age of the modified row is from just now
      let cacheReadExpectation = self.expectation(description: "cacheReadExpectation")
      store.withinReadTransaction ({ transaction in
        let object = try transaction.readObject(ofType: GivenSelectionSet.Hero.self, withKey: "QUERY_ROOT.hero")
        XCTAssertTrue(object.0.name == "Artoo")
        XCTAssertEqual(
          Calendar.current.compare(Date(), to: object.1.maxAge, toGranularity: .minute),
          .orderedSame
        )
      }, completion: { result in
        defer { cacheReadExpectation.fulfill() }
        XCTAssertSuccessResult(result)
      })
      self.wait(for: [cacheReadExpectation], timeout: Self.defaultWaitTimeout)
    }
  }
}

// MARK: - Helpers

extension CacheTests {
  private func testResulContextWhenLoadingHeroNameQueryWithAge(
    initialRecords: RecordSet,
    expectedResultAge: Date,
    file: StaticString = #file,
    line: UInt = #line
  ) throws {

    class HeroNameSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self)
        ]}
      }
    }

    let query = MockQuery<HeroNameSelectionSet>()
    mergeRecordsIntoCache(initialRecords)
    loadFromStore(operation: query) { result in
      switch result {
      case let .success(result):
        XCTAssertNil(result.errors, file: file, line: line)
        XCTAssertEqual(result.data?.hero?.name, "R2-D2", file: file, line: line)
        XCTAssertEqual(
          Calendar.current.compare(expectedResultAge, to: result.metadata.maxAge, toGranularity: .minute),
          .orderedSame,
          file: file,
          line: line
        )
      case let .failure(error):
        XCTFail("Unexpected error: \(error)", file: file, line: line)
      }
    }
  }
}

extension RecordSet {
  init(_ dictionary: Dictionary<CacheKey, (fields: Record.Fields, receivedAt: Date)>) {
    self.init(rows: dictionary.map { element in
      RecordRow(
        record: Record(key: element.key, element.value.fields),
        lastReceivedAt: element.value.receivedAt
      )
    })
  }
}
