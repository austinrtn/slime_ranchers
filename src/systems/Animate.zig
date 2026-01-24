const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;

pub const Animate = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    active: bool = true,
    queries: struct {
        sprites: Query(.{.read = &.{}, .write = &.{.Sprite}}),
    },

    pub fn update(self: *Self) !void {
        try self.queries.sprites.forEach(null, struct{
            pub fn run(_: anytype, c: anytype) !bool {
                c.Sprite.nextFrame();
                return true;
            }
        });
    }
};
