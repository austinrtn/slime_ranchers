const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const SR = @import("../registries/SystemRegistry.zig");
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;
const raylib = @import("raylib");
const Phase = @import("../registries/Phases.zig").Phase;

pub const HealthManager = struct {
    const Self = @This();
    pub const enabled = true;
    pub const phase: Phase = .Update;
    // Optional: resolve write-write conflicts with other systems
    // pub const runs_before = &[_]SR.SystemName{ .OtherSystem };

    // Optional: declare indirect component access (through entity references)
    // pub const indirect_reads = &.{};
    // pub const indirect_writes = &.{};

    allocator: std.mem.Allocator,
    active: bool = true,
    queries: struct {
        player: Query(.{
            .read = &.{.Controller},   // *const T - cannot mutate
            .write = &.{.Health},  // *T - can mutate (implies read access)
        }),
    },

    pub fn update(self: *Self) !void {
        try self.queries.player.forEach(self, struct {
            pub fn run(ctx: anytype, c: anytype) !bool {
                _ = ctx;
                const health = c.Health;
                if(!health.queue_damage) return true;

                if(!health.taking_damange) {
                    health.health -= 3;
                    health.taking_damange = true;
                } else {
                    health.time_acc += raylib.getFrameTime();
                    if(health.time_acc >= health.time_invincible) {
                        health.taking_damange = false;
                        health.queue_damage = false;
                        health.time_acc = 0;
                    }
                }
                return true;  
            }
        });
    }
};
