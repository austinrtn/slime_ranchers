const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;
const raylib = @import("raylib");

pub const Controller = struct {
    const Self = @This();
    pub const enabled: bool = true;
    pub const runs_before = &.{.Animate, .Attack, .ChangeAnim, .EnergyManager, .Track, .WaveManager};

    allocator: std.mem.Allocator,
    active: bool = true,
    wave_factory: Prescient.Factories.WaveFactory = undefined, 
    queries: struct {
        controllables: Query(.{.read = &.{.Controller, .Speed}, .write = &.{.Slime, .Sprite, .Velocity, .Attack}}),
    },

    pub fn init(self: *Self) !void {
        self.wave_factory = try Prescient.Factories.WaveFactory.init();
    }

    pub fn update(self: *Self) !void {
        try self.queries.controllables.forEach(self, struct{
            pub fn run(data: anytype, c: anytype) !bool {
                const ent = c.entity;
                const slime = c.Slime;
                const vel = c.Velocity;
                const spd = c.Speed;
                const sprite = c.Sprite;
                const atk = c.Attack;

                if(slime.state == .attacking) {
                    if(sprite.animation_complete) {
                        slime.state = .idling;
                        atk.recovering = true;
                    }
                }
                else if(raylib.isKeyDown(.space) and atk.can_attack) {
                    sprite.frame_index = 0;
                    sprite.delay_counter = 0;
                    sprite.animation_complete = false;
                    slime.state = .attacking;
                    //var factory = Prescient.Factory.WaveFactory.init();
                    _ = try data.wave_factory.spawn(.{ .position = .{.x = 0, .y = 0}, .slime_ref = ent});
                }
                if(slime.state != .attacking and slime.state != .recovering){
                    //UP & DOWN
                    if(raylib.isKeyDown(.down)) {
                        vel.dy = spd.*;
                        slime.state = .moving;
                    }
                    else if(raylib.isKeyDown(.up)) {
                        vel.dy = -1 * spd.*;
                        slime.state = .moving;
                    }
                    else {
                        vel.dy = 0;
                    }
                    //LEFT & RIGHT
                    if(raylib.isKeyDown(.left)) {
                        vel.dx = -1 * spd.*;
                        slime.state = .moving;
                    }
                    else if(raylib.isKeyDown(.right)) {
                        vel.dx = spd.*;
                        slime.state = .moving;
                    }
                    else {
                        vel.dx = 0;
                    }
                }
                if (
                    slime.state != .attacking
                    and slime.state != .recovering and
                    (raylib.isKeyUp(.up) and raylib.isKeyUp(.down) and raylib.isKeyUp(.left) and raylib.isKeyUp(.right))
                ) {
                    slime.state = .idling;
                }

                if(slime.state == .idling or slime.state == .recovering) {
                    vel.dx = 0;
                    vel.dy = 0;
                }
                return true;
            }
        });
    }
};
