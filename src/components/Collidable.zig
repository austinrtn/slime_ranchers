const Prescient = @import("../ecs/Prescient.zig").Prescient;

pub const Collidable = struct {
    active: bool = true,

    // Optional custom collision box dimensions (unscaled)
    // If not set (0), will use full sprite frame dimensions
    width: f32 = 0,
    height: f32 = 0,

    // Optional offset from sprite center (unscaled)
    offset_x: f32 = 0,
    offset_y: f32 = 0,
};
