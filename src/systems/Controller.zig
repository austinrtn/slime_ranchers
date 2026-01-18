const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;
const raylib = @import("raylib");

pub const Controller = struct {
    const Self = @This();

    // Dependency declarations for compile-time system ordering
    pub const reads = [_]type{};
    pub const writes = [_]type{};

    allocator: std.mem.Allocator,
    active: bool = true,
    queries: struct {
        controllables: Query(&.{.Slime, .Sprite, .Controller, .Velocity, .Speed}),
    },

    pub fn update(self: *Self) !void {
        while(try self.queries.controllables.next()) |b| {
            for(b.Slime, b.Velocity, b.Speed, b.Sprite) |slime, vel, spd, sprite| {
                if(slime.state == .attacking) {
                    if(sprite.frame_index == sprite.animation_length - 1){
                        slime.state = .idling;
                    }
                }
                else if(raylib.isKeyDown(.space) and slime.state != .attacking) {
                    sprite.frame_index = 0;
                    sprite.delay_counter = 0;
                    slime.state = .attacking;
                }
                if(slime.state != .attacking){
                    if(raylib.isKeyDown(.down)) {
                        vel.dy = spd.*;
                        slime.state = .moving;
                    } 
                    if(raylib.isKeyDown(.right)) {
                        vel.dx = spd.*;
                        slime.state = .moving;
                    } 
                    if(raylib.isKeyDown(.left)) {
                        vel.dx = -1 * spd.*;
                        slime.state = .moving;
                    } 
                    if(raylib.isKeyDown(.up)) {
                        vel.dy = -1 * spd.*;
                        slime.state = .moving;
                    } 
                    if (raylib.isKeyUp(.up) and raylib.isKeyUp(.down) and raylib.isKeyUp(.left) and raylib.isKeyUp(.right)) {
                        vel.dx = 0;
                        vel.dy = 0;
                        slime.state = .idling;
                    }
                }
            }
        }
    }
};
