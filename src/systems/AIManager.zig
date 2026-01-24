const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const SR = @import("../registries/SystemRegistry.zig");
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;

pub const AIManager = struct {
    const Self = @This();
    pub const enabled: bool = true;

    // Optional: resolve write-write conflicts with other systems
    // pub const runs_before = &[_]SR.SystemName{ .OtherSystem };

    allocator: std.mem.Allocator,
    active: bool = true,
    queries: struct {
        slimes: Query(.{
            .read = &.{},  
            .write = &.{.AI}, 
        }),
    },

    pub fn update(self: *Self) !void {
        try self.queries.slimes.forEach(self, struct {
            pub fn run(ctx: anytype, c: anytype) !bool {
                _ = ctx;
                const ai: Prescient.Components.Types.AI = c.AI.*;
                _=ai;//if(ai. ) 
                return true;  // continue (return false to stop iteration)
            }
        });
    }
};
