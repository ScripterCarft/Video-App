import Foundation

extension String {
    /// The text with every run of whitespace and newlines collapsed to a
    /// single space, or `nil` when nothing but whitespace remains.
    var collapsedWhitespace: String? {
        let collapsed = split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }
}
