import Foundation

/// Sanitize a string for use as a filename by replacing illegal characters with hyphens.
func sanitizeFilename(_ name: String) -> String {
    let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
    return name.components(separatedBy: illegal).joined(separator: "-")
}
