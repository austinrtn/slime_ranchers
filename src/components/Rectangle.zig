const raylib = @import("raylib");

pub const Rectangle = struct {
    width: f32,
    height: f32,

    pub fn getVector(self: @This()) raylib.Vector2 {
        return .{
            .x = self.width,
            .y = self.height,
        };
    }
};
