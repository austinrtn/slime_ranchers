const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;
const Raylib = @import("raylib");

pub const Track = struct {
    const Self = @This();

    // Dependency declarations for compile-time system ordering
    pub const reads = [_]type{};
    pub const writes = [_]type{};

    allocator: std.mem.Allocator,
    active: bool = true,
    speed: f32 = 150,
    queries: struct {
        objs: Query(.{ .comps = &.{.Position, .Velocity} }),
    },

    pub fn update(self: *Self) !void {
        try self.queries.objs.forEach(self, struct{
            pub fn run(data: anytype, c: anytype) !bool {
                const pos = c.Position;
                const vel = c.Velocity;

                const pos_vect = Raylib.Vector2{.x = pos.x, .y = pos.y};
                const mouse = Raylib.getMousePosition();

                const dist = Raylib.Vector2.subtract(mouse, pos_vect);
                const length = Raylib.Vector2.length(dist);

                if(length > 150) {
                    vel.dx = 0;
                    vel.dy = 0;
                    return true;
                }

                const velocity = Raylib.Vector2.scale(Raylib.Vector2.normalize(dist), data.speed);

                vel.dx = velocity.x;
                vel.dy = velocity.y;
                return true;
            }
        });
    }
};
