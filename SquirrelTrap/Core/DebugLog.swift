import Foundation

/// Compiles out entirely in Release — these calls were shipping unconditionally
/// to end users' Console.app since v1.2.0. Message strings already include their
/// own "Squirrel Trap DEBUG: ..." prefix and trailing newline, unchanged from
/// their original FileHandle.standardError.write call sites.
func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    FileHandle.standardError.write(message().data(using: .utf8)!)
    #endif
}
