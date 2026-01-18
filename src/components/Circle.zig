const Prescient = @import("../ecs/Prescient.zig").Prescient;
const raylib = @import("raylib");

pub const Circle = struct {
    radius: f32,
    color: raylib.Color = .red,
};
