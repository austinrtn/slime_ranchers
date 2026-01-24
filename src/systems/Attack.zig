const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;
const raylib = @import("raylib");

pub const Attack = struct {
    const Self = @This();
    // Removed runs_before - EnergyManager writes Slime which Attack reads,
    // so EnergyManager should run first (component dependency handles this)

    allocator: std.mem.Allocator,
    active: bool = true,
    queries: struct {
        slime: Query(.{.read = &.{.Slime, .Energy}, .write = &.{.Attack}}),
    },

    pub fn update(self: *Self) !void {
        try self.queries.slime.forEach(null, struct{
            pub fn run(_: anytype, c: anytype) !bool {
                const slime = c.Slime;
                const atk = c.Attack;
                const energy = c.Energy;

                if(
                    slime.state == .recovering or
                    slime.state == .attacking or
                    (energy.energy - energy.attack_cost) < 0 or
                    atk.recovering
                ){
                    atk.can_attack = false;
                } else atk.can_attack = true;
                if(atk.recovering) {
                    atk.time_since_last_attack += raylib.getFrameTime();
                    if(atk.time_since_last_attack >= atk.timeout) {
                        atk.time_since_last_attack = 0;
                        atk.recovering = false;
                    }
                }
                return true;
            }
        });
    }
};
