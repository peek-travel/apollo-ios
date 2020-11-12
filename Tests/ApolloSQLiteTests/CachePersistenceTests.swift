import XCTest
@testable import Apollo
@testable import ApolloSQLite
import ApolloTestSupport
import ApolloSQLiteTestSupport
import StarWarsAPI
import SQLite

class CachePersistenceTests: XCTestCase {

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

          // verify that the current schema version is now incremented from the snapshot
          let schemaVersion = try sqlCache.readSchemaVersion()
          XCTAssertEqual(schemaVersion, Int64(previousSchemaVersion + 1))

          // inserts some entries in the database to verify the file is useable after the migration
          runTestFetchAndPersist(againstFileAt: fileURL)
        }
      }
  }

  func testFetchAndPersist() {
    self.runTestFetchAndPersist(againstFileAt: SQLiteTestCacheProvider.temporarySQLiteFileURL())
  }

  func testPassInConnectionDoesNotThrow() {
    XCTAssertNoThrow(try SQLiteNormalizedCache(db: Connection()))
  }
}

// MARK: Cache clearing

extension CachePersistenceTests {
  func testClearMatchingKeyPattern() {
    let notFoundExpectation = self.expectation(description: "records should not exist")

    self.testCacheClearing(withPolicy: .allMatchingKeyPattern("*hero*")) { client, _ in
      client.store.withinReadTransaction {
        $0.loadRecords(forKeys: ["QUERY_ROOT.hero", "QUERY_ROOT.hero(episode:EMPIRE)"]) { result in
          defer { notFoundExpectation.fulfill() }

          do {
            let results = try result.get()
            XCTAssertTrue(results.allSatisfy({ $0 == nil }))
          } catch {
            XCTFail("Unexpected error: \(error)")
          }
        }
      }
    }
  }

  func testClearAllRecords() {
    let emptyCacheExpectation = self.expectation(description: "Fetch query from empty cache")

    self.testCacheClearing(withPolicy: .allRecords) { client, query in
      client.fetch(query: query, cachePolicy: .returnCacheDataDontFetch) {
        defer { emptyCacheExpectation.fulfill() }

        do {
          _ = try $0.get()
          XCTFail("This should have returned an error")
        } catch let error as JSONDecodingError {
          // we're expecting this error
          guard case .missingValue = error else {
            XCTFail("Unexpected JSON error: \(error)")
            return
          }
        } catch {
          XCTFail("Unexpected error: \(error)")
        }
      }
    }
  }

  func testClearByDate() {
    let emptyCacheExpectation = self.expectation(description: "empty cache")

    self.testCacheClearing(withPolicy: .allMatchingKeyPattern("*hero*")) { client, _ in
      client.store.withinReadTransaction {
        $0.loadRecords(forKeys: ["QUERY_ROOT.hero", "QUERY_ROOT.hero(episode:EMPIRE)"]) { result in
          defer { emptyCacheExpectation.fulfill() }

          do {
            let results = try result.get()
            XCTAssertTrue(results.allSatisfy({ $0 == nil }))
          } catch {
            XCTFail("Unexpected error: \(error)")
          }
        }
      }
    }
  }

  private func testCacheClearing(
    withPolicy policy: CacheClearingPolicy,
    validateAssumptions: @escaping (ApolloClient, TwoHeroesQuery) throws -> Void,
    file: StaticString = #file, line: UInt = #line
  ) rethrows {
    let query = TwoHeroesQuery()
    let sqliteFileURL = SQLiteTestCacheProvider.temporarySQLiteFileURL()

    SQLiteTestCacheProvider.withCache(fileURL: sqliteFileURL) { (cache) in
      let store = ApolloStore(cache: cache)
      let networkTransport = MockNetworkTransport(body: [
        "data": [
          "luke": ["name": "Luke Skywalker", "__typename": "Human"],
          "r2": ["name": "R2-D2", "__typename": "Droid"]
        ]
      ], store: store)
      let client = ApolloClient(networkTransport: networkTransport, store: store)

      let networkExpectation = self.expectation(description: "Fetching query from network")
      let cacheClearExpectation = self.expectation(description: "cache cleared")

      // load the cache for the test
      client.fetch(query: query, cachePolicy: .fetchIgnoringCacheData) { initialResult in
        defer { networkExpectation.fulfill() }

        // sanity check that the test is ready
        do {
          let data = try initialResult.get().data
          XCTAssertEqual(data?.luke?.name, "Luke Skywalker", file: file, line: line)
        } catch {
          XCTFail("Unexpected failure: \(error)", file: file, line: line)
          return
        }

        // clear the cache as specified for the test
        client.clearCache(usingPolicy: policy) { result in
          switch result {
          case .success: break
          case let .failure(error): XCTFail("Error clearing cache: \(error)", file: file, line: line)
          }
          cacheClearExpectation.fulfill()
        }

        // validate the test
        do {
          try validateAssumptions(client, query)
        } catch {
          XCTFail("Unexpected error \(error)", file: file, line: line)
        }
      }

      self.waitForExpectations(timeout: 2)
    }
  }
}

extension CachePersistenceTests {
  private func runTestFetchAndPersist(
    againstFileAt sqliteFileURL: URL,
    file: StaticString = #file,
    line: UInt = #line
  ) {
      let query = HeroNameQuery()

      SQLiteTestCacheProvider.withCache(fileURL: sqliteFileURL) { (cache) in
        let store = ApolloStore(cache: cache)
        let networkTransport = MockNetworkTransport(body: [
          "data": [
            "hero": [
              "name": "Luke Skywalker",
              "__typename": "Human"
            ]
          ]
        ], store: store)
        let client = ApolloClient(networkTransport: networkTransport, store: store)

        let networkExpectation = self.expectation(description: "Fetching query from network")
        let newCacheExpectation = self.expectation(description: "Fetch query from new cache")

        client.fetch(query: query, cachePolicy: .fetchIgnoringCacheData) { outerResult in
          defer { networkExpectation.fulfill() }

          switch outerResult {
          case .failure(let error):
            XCTFail("Unexpected error: \(error)", file: file, line: line)
            return
          case .success(let graphQLResult):
            XCTAssertEqual(graphQLResult.data?.hero?.name, "Luke Skywalker", file: file, line: line)
            // Do another fetch from cache to ensure that data is cached before creating new cache
            client.fetch(query: query, cachePolicy: .returnCacheDataDontFetch) { innerResult in
              SQLiteTestCacheProvider.withCache(fileURL: sqliteFileURL) { cache in
                let newStore = ApolloStore(cache: cache)
                let newClient = ApolloClient(networkTransport: networkTransport, store: newStore)
                newClient.fetch(query: query, cachePolicy: .returnCacheDataDontFetch) { newClientResult in
                  defer { newCacheExpectation.fulfill() }
                  switch newClientResult {
                  case .success(let newClientGraphQLResult):
                    XCTAssertEqual(newClientGraphQLResult.data?.hero?.name, "Luke Skywalker", file: file, line: line)
                  case .failure(let error):
                    XCTFail("Unexpected error with new client: \(error)", file: file, line: line)
                  }
                  _ = newClient // ensure that newClient is retained until this block is run
                }
              }
            }
          }
        }

        self.waitForExpectations(timeout: 2, handler: nil)
      }
  }
}
