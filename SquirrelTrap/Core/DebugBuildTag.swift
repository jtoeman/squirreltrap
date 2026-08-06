import Foundation

#if DEBUG
/// Bumped by hand for every build handed over for testing, so the main
/// panel's header can show e.g. "Squirrel Trap (b)" -- confirms you're
/// running the exact build just produced, not a stale cached one. Reset to
/// "a" whenever the real version number changes. Never compiled into
/// Release builds, so it can never leak into a shipped app.
let debugBuildTag = "a"
#endif
