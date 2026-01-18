const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;
const raylib = @import("raylib");

pub const EnergyManager = struct {
    const Self = @This();

    // Dependency declarations for compile-time system ordering
    pub const reads = [_]type{};
    pub const writes = [_]type{};

    allocator: std.mem.Allocator,
    active: bool = true,
    queries: struct {
        slimes: Query(&.{.Energy, .Slime})
    },

    pub fn update(self: *Self) !void {
        while(try self.queries.slimes.next()) |b| {
            for(b.Energy, b.Slime) |energy, slime| {
                if(energy.energy < energy.max_energy and slime.state == .idling) {
                    energy.energy += energy.regen_per_frame * raylib.getFrameTime();
                }

                else if(energy.energy > 0 and slime.state == .moving) {
                    const movement_cost = energy.movement_cost * raylib.getFrameTime();
                    if((energy.energy - movement_cost) < 0) {
                        energy.energy = 0;
                    }
                    else energy.energy -= movement_cost;
                }

                if(energy.energy > energy.max_energy) {
                    energy.energy = energy.max_energy;
                }
                if(energy.energy <= 0) {
                    slime.state = .idling;
                    energy.energy = 0;
                }
                std.debug.print("\nEnergy:{}", .{energy.energy});
            }
        }
    }
};
