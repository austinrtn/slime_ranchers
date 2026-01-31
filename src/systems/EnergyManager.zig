const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;
const raylib = @import("raylib");
const Phase = @import("../registries/Phases.zig").Phase;

pub const EnergyManager = struct {
    const Self = @This();
    pub const enabled: bool = true;
    pub const phase: Phase = .Update;
    pub const runs_before = &.{.ChangeAnim};

    allocator: std.mem.Allocator,
    active: bool = true,
    prescient: *Prescient = undefined,
    queries: struct {
        slimes: Query(.{.read = &.{.Attack}, .write = &.{.Energy, .Slime}}),
    },

    pub fn init(self: *Self) !void {
        self.prescient = try Prescient.getPrescient();
    }

    pub fn update(self: *Self) !void {
        try self.queries.slimes.forEach(self, struct{
            pub fn run(data: anytype, c: anytype) !bool {
                _ = data;
                const energy = c.Energy;
                const slime = c.Slime;

                // Recover energy while idling
                if(energy.energy < energy.max_energy and (slime.state == .idling or slime.state == .recovering)) {
                    energy.energy += energy.regen_per_frame * raylib.getFrameTime();
                }

                // Force idle durring recovering state
                if(slime.state == .recovering) {
                    if(energy.energy >= energy.min_req){
                        slime.state = .idling;
                        return true;
                    }
                    return true;
                }

                // Spend Energy While Moving
                else if(energy.energy > 0 and slime.state == .moving) {
                    const movement_cost = energy.movement_cost * raylib.getFrameTime();
                    if((energy.energy - movement_cost) < 0) {
                        energy.energy = 0;
                    }
                    else energy.energy -= movement_cost;
                }

                // One time energy cost for attack
                else if(slime.state == .attacking and !energy.attack_reducted) {
                    energy.energy -= energy.attack_cost;
                    energy.attack_reducted = true;
                }

                //Reset attack reducted flag after attack finished
                if(slime.state != .attacking and energy.attack_reducted) {
                    energy.attack_reducted = false;
                }

                // Keep energy from exceding max
                if(energy.energy > energy.max_energy) {
                    energy.energy = energy.max_energy;
                }

                // Keep energy from sub 0
                if(energy.energy <= 0) {
                    energy.energy = 0;
                    slime.state = .recovering;
                }
                return true;
            }
        });
    }
};
