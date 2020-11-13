enum ApolloMath {

  static func min<T: Comparable>(_ a: T, _ b: T?) -> T {
    return Swift.min(a, b ?? a)
  }
}
