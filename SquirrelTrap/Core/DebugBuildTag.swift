import Foundation

#if DEBUG
/// The version being worked toward (bump when starting on a new release --
/// latest shipped tag is v1.5.0, so this is "1.6" until v1.6.0 ships), plus a
/// letter bumped by hand for every build handed over for testing. Shown in
/// the main panel header as e.g. "Squirrel Trap 1.6a" -- confirms you're
/// running the exact build just produced, not a stale cached one. Reset the
/// letter to "a" whenever debugNextVersion changes. Never compiled into
/// Release builds, so it can never leak into a shipped app.
let debugNextVersion = "1.6"
let debugBuildTag = "a"
#endif
