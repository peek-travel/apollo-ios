@testable import Apollo
import ApolloAPI
@testable import ApolloSQLite
import SQLite
import XCTest

final class SQLiteCacheTests: XCTestCase {
  func testDatabaseSetup() throws {
    // loop through each of the database snapshots to run through migrations
    // if a migration fails, then it will throw an error
    // we verify the migration is successful by comparing the iteration to the schema version (assigned after the migration)
    let testBundle = Bundle(for: Self.self)
    try testBundle.paths(forResourcesOfType: "sqlite3", inDirectory: nil)
      .sorted() // make sure they run in order
      .map(URL.init(fileURLWithPath:))
      .enumerated()
      .forEach { previousSchemaVersion, fileURL in
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
          XCTFail("expected snapshot file '\(fileURL.lastPathComponent)' could not be found")
          return
        }
        // open a connection to the snapshot that is expected to be migrated to the next version
        try SQLiteTestCacheProvider.withCache(fileURL: fileURL) { cache in
          guard let sqlCache = cache as? SQLiteNormalizedCache else {
            XCTFail("The cache is not using SQLite")
            return
          }
          let schemaVersion = try sqlCache.database.readSchemaVersion()
          XCTAssertEqual(schemaVersion, Int64(previousSchemaVersion + 1))

          runTestFetchAndPersist(againstFileAt: fileURL)
        }
      }
  }

  func testPassInConnectionDoesNotThrow() {
    do {
      let database = try SQLiteDotSwiftDatabase(connection: Connection())
      _ = try SQLiteNormalizedCache(database: database)

    } catch {
      XCTFail("Passing in connection failed with error: \(error)")
    }
  }
}

// MARK: - Helpers

extension SQLiteCacheTests {
  private func runTestFetchAndPersist(
    againstFileAt sqliteFileURL: URL,
    file: StaticString = #file,
    line: UInt = #line
  ) {
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

    let query = MockQuery<GivenSelectionSet>()
    try SQLiteTestCacheProvider.withCache(fileURL: sqliteFileURL) { (cache) in
      let store = ApolloStore(cache: cache)
      let server = MockGraphQLServer()
      let networkTransport = MockNetworkTransport(server: server, store: store)
      let client = ApolloClient(networkTransport: networkTransport, store: store)
      _ = server.expect(MockQuery<GivenSelectionSet>.self) { request in
        [
          "data": [
            "hero": [
              "name": "Luke Skywalker",
              "__typename": "Human"
            ]
          ]
        ]
      }

      let networkExpectation = self.expectation(description: "Fetching query from network")
      let newCacheExpectation = self.expectation(description: "Fetch query from new cache")

      client.fetch(query: query, cachePolicy: .fetchIgnoringCacheData) { outerResult in
        defer { networkExpectation.fulfill() }

        switch outerResult {
        case .failure(let error):
          XCTFail("Unexpected error: \(error)")
          return
        case .success(let graphQLResult):
          XCTAssertEqual(graphQLResult.data?.hero?.name, "Luke Skywalker")
          // Do another fetch from cache to ensure that data is cached before creating new cache
          client.fetch(query: query, cachePolicy: .returnCacheDataDontFetch) { innerResult in
            try! SQLiteTestCacheProvider.withCache(fileURL: sqliteFileURL) { cache in
              let newStore = ApolloStore(cache: cache)
              let newClient = ApolloClient(networkTransport: networkTransport, store: newStore)
              newClient.fetch(query: query, cachePolicy: .returnCacheDataDontFetch) { newClientResult in
                defer { newCacheExpectation.fulfill() }
                switch newClientResult {
                case .success(let newClientGraphQLResult):
                  XCTAssertEqual(newClientGraphQLResult.data?.hero?.name, "Luke Skywalker")
                case .failure(let error):
                  XCTFail("Unexpected error with new client: \(error)")
                }
                _ = newClient // Workaround for a bug - ensure that newClient is retained until this block is run
              }}
          }
        }
      }

      self.waitForExpectations(timeout: 2, handler: nil)
    }
  }
}
