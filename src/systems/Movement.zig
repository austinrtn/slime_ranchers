const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;
const raylib = @import("raylib");

pub const Movement = struct {
    const Self = @This();

    // Dependency declarations for compile-time system ordering
    pub const reads = [_]type{};
    pub const writes = [_]type{};

    allocator: std.mem.Allocator,
    active: bool = true,
    frame_time: f32 = 0,
    queries: struct {
        objs: Query(.{ .comps = &.{.Position, .Velocity} }),
    },

    pub fn init(self: *Self) !void {
        self.frame_time = raylib.getFrameTime(); 
    }

    pub fn update(self: *Self) !void {
        try self.queries.objs.forEach(self, struct{
            pub fn run(data: anytype, c: anytype) !bool {
                const pos = c.Position;
                const vel = c.Velocity;

                pos.x += vel.dx * data.frame_time;
                pos.y += vel.dy * data.frame_time;
                return true;
            }
        });
        self.frame_time = raylib.getFrameTime();
    }
};
