const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;
const raylib = @import("raylib");

pub const Attack = struct {
    const Self = @This();

    // Dependency declarations for compile-time system ordering
    pub const reads = [_]type{};
    pub const writes = [_]type{};

    allocator: std.mem.Allocator,
    active: bool = true,
    queries: struct {
        slime: Query(&.{.Slime, .Attack, .Energy},)
    },

    pub fn update(self: *Self) !void {
        while(try self.queries.slime.next()) |b| {
            for(b.Slime, b.Attack, b.Energy) |slime, atk, energy| {
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
            }
        }
    }
};
