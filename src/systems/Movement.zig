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
    queries: struct {
        objs: Query(.{ .comps = &.{.Position, .Velocity} }),
    },

    pub fn update(self: *Self) !void {
        while(try self.queries.objs.next()) |b| {
            for(b.Position, b.Velocity) |pos, vel| {
                pos.x += vel.dx * raylib.getFrameTime();
                pos.y += vel.dy * raylib.getFrameTime();
            }
        }
    }
};
