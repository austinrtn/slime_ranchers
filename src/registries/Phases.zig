// User-defined execution phases
// Edit this file to define your game's phase structure

pub const Phase = enum {
    Input,      // Process player input and AI decisions
    PreUpdate,  // Setup and preparation before main logic
    Update,     // Core game logic (physics, combat, collision)
    PostUpdate, // React to state changes, update animations and UI
    Render,     // Draw everything to screen
};

/// Order in which phases execute
pub const phase_sequence: []const Phase = &.{
    .Input,
    .PreUpdate,
    .Update,
    .PostUpdate,
    .Render,
};
