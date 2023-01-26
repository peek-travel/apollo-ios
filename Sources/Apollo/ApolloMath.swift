enum ApolloMath {

   static func min<T: Comparable>(_ a: T, _ b: T?) -> T {
     return b.map { min(a, $0) } ?? a
   }
 }
