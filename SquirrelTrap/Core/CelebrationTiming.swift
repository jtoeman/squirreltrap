import Foundation

/// Single adjustable knob for how long the task-completion celebration runs,
/// end to end (icon pulse + count pulse + row shrink/puff/reform) -- tweak
/// this one value to experiment with pacing. PromptPanelViewModel holds
/// isCelebrating true for exactly this long, and PromptPanelView times
/// every phase of the animation as a fraction of it.
let celebrationDuration: Double = 0.75
