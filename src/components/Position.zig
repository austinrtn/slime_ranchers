const Prescient = @import("../ecs/Prescient.zig").Prescient;
const raylib = @import("raylib");

pub const Position = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,

    pub fn getVector(self: *const @This()) raylib.Vector2 {
        return raylib.Vector2{
            .x = self.x,
            .y = self.y
        };
    }
};
