import XCTest
@testable import Apollo
import ApolloAPI
#if canImport(ApolloSQLite)
import ApolloSQLite
#endif
import ApolloInternalTestHelpers

class LoadQueryFromStoreTests: XCTestCase, CacheDependentTesting, StoreLoading {
  var cacheType: TestCacheProvider.Type {
    InMemoryTestCacheProvider.self
  }

  static let defaultWaitTimeout: TimeInterval = 5.0

  var cache: NormalizedCache!
  var store: ApolloStore!
  
  override func setUpWithError() throws {
    try super.setUpWithError()
    
    cache = try makeNormalizedCache()
    store = ApolloStore(cache: cache)
  }
  
  override func tearDownWithError() throws {
    cache = nil
    store = nil
    
    try super.tearDownWithError()
  }
  
  func testLoadingHeroNameQuery() throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
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

    mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": ["__typename": "Droid", "name": "R2-D2"]
    ])

    // when
    let query = MockQuery<GivenSelectionSet>()
    
    loadFromStore(operation: query) { result in
      // then
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)
        
        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "R2-D2")
      }
    }
  }
  
  func testLoadingHeroNameQueryWithVariable() throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self, arguments: ["episode": .variable("episode")])
      ]}

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self)
        ]}
      }
    }

    mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero(episode:JEDI)": CacheReference("hero(episode:JEDI)")],
      "hero(episode:JEDI)": ["__typename": "Droid", "name": "R2-D2"]
    ])

    // when
    let query = MockQuery<GivenSelectionSet>()
    query.__variables = ["episode": "JEDI"]
    
    loadFromStore(operation: query) { result in
      // then
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)
        
        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero?.name, "R2-D2")
      }
    }
  }
  
  func testLoadingHeroNameQueryWithMissingName_throwsMissingValueError() throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
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

    mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": ["__typename": "Droid"]
    ])

    // when
    let query = MockQuery<GivenSelectionSet>()
    
    loadFromStore(operation: query) { result in
      // then
      XCTAssertThrowsError(try result.get()) { error in
        if let error = error as? GraphQLExecutionError {
          XCTAssertEqual(error.path, ["hero", "name"])
          XCTAssertMatch(error.underlying, JSONDecodingError.missingValue)
        } else {
          XCTFail("Unexpected error: \(error)")
        }
      }
    }
  }
  
  func testLoadingHeroNameQueryWithNullName_throwsNullValueError() throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
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

    mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": ["__typename": "Droid", "name": NSNull()]
    ])
    
    // when
    let query = MockQuery<GivenSelectionSet>()
    
    loadFromStore(operation: query) { result in
      // then
      XCTAssertThrowsError(try result.get()) { error in
        if let error = error as? GraphQLExecutionError {
          XCTAssertEqual(error.path, ["hero", "name"])
          XCTAssertMatch(error.underlying, JSONDecodingError.nullValue)
        } else {
          XCTFail("Unexpected error: \(error)")
        }
      }
    }
  }
  
  func testLoadingHeroAndFriendsNamesQueryWithoutIDs() throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}
      var hero: Hero { __data["hero"] }

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
          .field("friends", [Friend].self)
        ]}
        var friends: [Friend] { __data["friends"] }

        class Friend: MockSelectionSet {
          override class var __selections: [Selection] {[
            .field("__typename", String.self),
            .field("name", String.self)
          ]}
          var name: String { __data["name"] }
        }
      }
    }

    mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": [
        "name": "R2-D2",
        "__typename": "Droid",
        "friends": [
          CacheReference("hero.friends.0"),
          CacheReference("hero.friends.1"),
          CacheReference("hero.friends.2")
        ]
      ],
      "hero.friends.0": ["__typename": "Human", "name": "Luke Skywalker"],
      "hero.friends.1": ["__typename": "Human", "name": "Han Solo"],
      "hero.friends.2": ["__typename": "Human", "name": "Leia Organa"],
    ])

    // when
    let query = MockQuery<GivenSelectionSet>()

    loadFromStore(operation: query) { result in
      // then
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)
        
        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero.name, "R2-D2")
        let friendsNames = data.hero.friends.compactMap { $0.name }
        XCTAssertEqual(friendsNames, ["Luke Skywalker", "Han Solo", "Leia Organa"])
      }
    }
  }
  
  func testLoadingHeroAndFriendsNamesQueryWithIDs() throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}
      var hero: Hero { __data["hero"] }

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
          .field("friends", [Friend].self)
        ]}
        var friends: [Friend] { __data["friends"] }

        class Friend: MockSelectionSet {
          override class var __selections: [Selection] {[
            .field("__typename", String.self),
            .field("name", String.self)
          ]}
          var name: String { __data["name"] }
        }
      }
    }

    mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("2001")],
      "2001": [
        "name": "R2-D2",
        "__typename": "Droid",
        "friends": [
          CacheReference("1000"),
          CacheReference("1002"),
          CacheReference("1003"),
        ]
      ],
      "1000": ["__typename": "Human", "name": "Luke Skywalker"],
      "1002": ["__typename": "Human", "name": "Han Solo"],
      "1003": ["__typename": "Human", "name": "Leia Organa"],
    ])
    
    // when
    let query = MockQuery<GivenSelectionSet>()

    loadFromStore(operation: query) { result in
      // then
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)
        
        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero.name, "R2-D2")
        let friendsNames = data.hero.friends.compactMap { $0.name }
        XCTAssertEqual(friendsNames, ["Luke Skywalker", "Han Solo", "Leia Organa"])
      }
    }
  }
  
  func testLoadingHeroAndFriendsNamesQuery_withOptionalFriendsSelection_withNullFriends() throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}
      var hero: Hero { __data["hero"] }

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
          .field("friends", [Friend]?.self)
        ]}
        var friends: [Friend]? { __data["friends"] }

        class Friend: MockSelectionSet {
          override class var __selections: [Selection] {[
            .field("__typename", String.self),
            .field("name", String.self)
          ]}
          var name: String { __data["name"] }
        }
      }
    }

    mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": [
        "name": "R2-D2",
        "__typename": "Droid",
        "friends": NSNull(),
      ]
    ])
    
    // when
    let query = MockQuery<GivenSelectionSet>()
    
    loadFromStore(operation: query) { result in
      // then
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)
        
        let data = try XCTUnwrap(graphQLResult.data)
        XCTAssertEqual(data.hero.name, "R2-D2")
        XCTAssertNil(data.hero.friends)
      }
    }
  }
  
  func testLoadingHeroAndFriendsNamesQuery_withOptionalFriendsSelection_withFriendsNotInCache_throwsMissingValueError() throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}
      var hero: Hero { __data["hero"] }

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
          .field("friends", [Friend]?.self)
        ]}
        var friends: [Friend]? { __data["friends"] }

        class Friend: MockSelectionSet {
          override class var __selections: [Selection] {[
            .field("__typename", String.self),
            .field("name", String.self)
          ]}
          var name: String { __data["name"] }
        }
      }
    }

    mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("hero")],
      "hero": ["__typename": "Droid", "name": "R2-D2"]
    ])
    
    // when
    let query = MockQuery<GivenSelectionSet>()
    
    loadFromStore(operation: query) { result in
      // then
      XCTAssertThrowsError(try result.get()) { error in
        if let error = error as? GraphQLExecutionError {
          XCTAssertEqual(error.path, ["hero", "friends"])
          XCTAssertMatch(error.underlying, JSONDecodingError.missingValue)
        } else {
          XCTFail("Unexpected error: \(error)")
        }
      }
    }
  }
  
  func testLoadingWithBadCacheSerialization() throws {
    // given
    class GivenSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("hero", Hero.self)
      ]}
      var hero: Hero { __data["hero"] }

      class Hero: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
          .field("friends", [Friend]?.self)
        ]}
        var friends: [Friend]? { __data["friends"] }

        class Friend: MockSelectionSet {
          override class var __selections: [Selection] {[
            .field("__typename", String.self),
            .field("name", String.self)
          ]}
          var name: String { __data["name"] }
        }
      }
    }

    mergeRecordsIntoCache([
      "QUERY_ROOT": ["hero": CacheReference("2001")],
      "2001": [
        "name": "R2-D2",
        "__typename": "Droid",
        "friends": [
          CacheReference("1000"),
          CacheReference("1002"),
          CacheReference("1003")
        ]
      ],
      "1000": ["__typename": "Human", "name": ["dictionary": "badValues", "nested bad val": ["subdictionary": "some value"] ]
      ],
      "1002": ["__typename": "Human", "name": "Han Solo"],
      "1003": ["__typename": "Human", "name": "Leia Organa"],
    ])
    
    // when
    let query = MockQuery<GivenSelectionSet>()
    
    loadFromStore(operation: query) { result in
      XCTAssertThrowsError(try result.get()) { error in
        // then
        if let error = error as? GraphQLExecutionError,
           case JSONDecodingError.couldNotConvert(_, let expectedType) = error.underlying {
          XCTAssertEqual(error.path, ["hero", "friends", "0", "name"])
          XCTAssertTrue(expectedType == String.self)
        } else {
          XCTFail("Unexpected error: \(error)")
        }
      }
    }
  }
  
  func testLoadingQueryWithFloats() throws {
    // given
    let starshipLength: Float = 1234.5
    let coordinates: [[Double]] = [[38.857150, -94.798464]]

    class GivenSelectionSet: MockSelectionSet {
      override class var __selections: [Selection] { [
        .field("starshipCoordinates", Starship.self)
      ]}

      class Starship: MockSelectionSet {
        override class var __selections: [Selection] {[
          .field("__typename", String.self),
          .field("name", String.self),
          .field("length", Float.self),
          .field("coordinates", [[Double]].self)
        ]}
      }
    }
    
    mergeRecordsIntoCache([
      "QUERY_ROOT": ["starshipCoordinates": CacheReference("starshipCoordinates")],
      "starshipCoordinates": ["__typename": "Starship",
                              "name": "Millennium Falcon",
                              "length": starshipLength,
                              "coordinates": coordinates]
    ])
    
    // when
    let query = MockQuery<GivenSelectionSet>()
    
    loadFromStore(operation: query) { result in
      // then
      try XCTAssertSuccessResult(result) { graphQLResult in
        XCTAssertEqual(graphQLResult.source, .cache)
        XCTAssertNil(graphQLResult.errors)
        
        let data = try XCTUnwrap(graphQLResult.data)
        let coordinateData: GivenSelectionSet.Starship? = data.starshipCoordinates
        XCTAssertEqual(coordinateData?.name, "Millennium Falcon")
        XCTAssertEqual(coordinateData?.length, starshipLength)
        XCTAssertEqual(coordinateData?.coordinates, coordinates)
      }
    }
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

}

// MARK: - Helpers

extension LoadQueryFromStoreTests {
  
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
