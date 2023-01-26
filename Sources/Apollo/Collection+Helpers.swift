import Foundation

// MARK: - Unzipping
// MARK: Arrays of tuples to tuples of arrays

public func unzip<Element1, Element2>(_ array: [(Element1?, Element2?)]) -> ([Element1], [Element2]) {
  var array1: [Element1] = []
  var array2: [Element2] = []

  for elements in array {
    if let element1 = elements.0 { array1.append(element1) }
    if let element2 = elements.1 { array2.append(element2) }
  }

  return (array1, array2)
}

public func unzip<Element1, Element2, Element3>(_ array: [(Element1?, Element2?, Element3?)]) -> ([Element1], [Element2], [Element3]) {
  var array1: [Element1] = []
  var array2: [Element2] = []
  var array3: [Element3] = []

  for elements in array {
    if let element1 = elements.0 { array1.append(element1) }
    if let element2 = elements.1 { array2.append(element2) }
    if let element3 = elements.2 { array3.append(element3) }
  }

  return (array1, array2, array3)
}

public func unzip<Element1, Element2, Element3, Element4>(_ array: [(Element1, Element2, Element3, Element4)]) -> ([Element1], [Element2], [Element3], [Element4]) {
   var array1: [Element1] = []
   var array2: [Element2] = []
   var array3: [Element3] = []
   var array4: [Element4] = []

   for element in array {
     array1.append(element.0)
     array2.append(element.1)
     array3.append(element.2)
     array4.append(element.3)
   }

   return (array1, array2, array3, array4)
 }
