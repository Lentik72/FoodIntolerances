import Foundation

protocol NumericConvertible {
    func toDouble() -> Double
}

extension Int: NumericConvertible {
    func toDouble() -> Double { Double(self) }
}

extension Double: NumericConvertible {
    func toDouble() -> Double { self }
}

extension Float: NumericConvertible {
    func toDouble() -> Double { Double(self) }
}

extension Collection where Element: NumericConvertible {
    func average() -> Double? {
        guard !isEmpty else { return nil }
        
        let total = reduce(0.0) { partialResult, element in
            partialResult + element.toDouble()
        }
        
        return total / Double(count)
    }
}
