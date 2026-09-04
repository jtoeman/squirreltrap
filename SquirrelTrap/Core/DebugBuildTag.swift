import Foundation

#if DEBUG
/// The version being worked toward (bump when starting on a new release --
/// latest shipped tag is v1.8.0, so this is "1.8.1" until v1.8.1 ships), plus
/// a letter bumped by hand for every build handed over for testing. Shown in
/// the main panel header as e.g. "Squirrel Trap 1.8.1a" -- confirms you're
/// running the exact build just produced, not a stale cached one. Reset the
/// letter to "a" whenever debugNextVersion changes. Never compiled into
/// Release builds, so it can never leak into a shipped app.
let debugNextVersion = "1.8.1"
let debugBuildTag = "f"
#endif
