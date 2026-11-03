import Foundation

/// Compares decimal priorities without limiting them to a machine-sized integer.
enum Priority {
    static func normalize(_ input: String) -> String? {
        var digits = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNegative = digits.first == "-"
        if isNegative || digits.first == "+" {
            digits.removeFirst()
        }

        // Accept only ASCII decimal digits; signs are handled separately above.
        let decimalDigits = UInt8(ascii: "0")...UInt8(ascii: "9")
        guard !digits.isEmpty, digits.utf8.allSatisfy(decimalDigits.contains) else { return nil }

        // Canonicalize leading zeroes and negative zero before storing or comparing.
        let significantDigits = String(digits.drop(while: { $0 == "0" }))
        let magnitude = significantDigits.isEmpty ? "0" : significantDigits
        return isNegative && magnitude != "0" ? "-" + magnitude : magnitude
    }

    static func isHigher(_ lhs: String, than rhs: String) -> Bool {
        let left = normalize(lhs) ?? "0"
        let right = normalize(rhs) ?? "0"
        let leftIsNegative = left.first == "-"
        let rightIsNegative = right.first == "-"
        if leftIsNegative != rightIsNegative { return !leftIsNegative }

        let leftMagnitude = leftIsNegative ? String(left.dropFirst()) : left
        let rightMagnitude = rightIsNegative ? String(right.dropFirst()) : right

        // With leading zeroes removed, digit count determines magnitude. Equal-length
        // decimal strings can be compared lexically. Negative numbers reverse both rules.
        if leftMagnitude.count != rightMagnitude.count {
            return leftIsNegative
                ? leftMagnitude.count < rightMagnitude.count
                : leftMagnitude.count > rightMagnitude.count
        }
        return leftIsNegative ? leftMagnitude < rightMagnitude : leftMagnitude > rightMagnitude
    }
}
