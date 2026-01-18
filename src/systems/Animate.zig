const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;

pub const Animate = struct {
    const Self = @This();

    // Dependency declarations for compile-time system ordering
    pub const reads = [_]type{};
    pub const writes = [_]type{.Sprite};

    allocator: std.mem.Allocator,
    active: bool = true,
    queries: struct {
        sprites: Query(&.{.Sprite}),
    },

    pub fn update(self: *Self) !void {
        while(try self.queries.sprites.next()) |b| {
            for(b.Sprite) |sprite| {
                sprite.nextFrame();
            }
        }
    }
};
