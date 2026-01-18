const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;
const raylib = @import("raylib");

pub const ChangeAnim = struct {
    const Self = @This();

    // Dependency declarations for compile-time system ordering
    pub const reads = [_]type{};
    pub const writes = [_]type{};

    allocator: std.mem.Allocator,
    active: bool = true,
    queries: struct {
        slimes: Query(&.{.Slime, .Velocity, .Texture, .Sprite}),
    },

    pub fn update(self: *Self) !void {
        while(try self.queries.slimes.next()) |b| {
            for(b.Slime, b.Velocity, b.Texture, b.Sprite) |slime, vel, texture, sprite| {
                if(slime.state == slime.last_state) continue;

                sprite.frame_index = 0;
                sprite.delay_counter = 0;
                
                if(slime.state == .attacking) {
                    slime.current_texture = slime.attack_texture; 
                }
                else if(vel.dx != 0 or vel.dy != 0) {
                    slime.current_texture = slime.moving_texture; 
                    slime.state = .moving;
                } 
                else {
                    slime.current_texture = slime.idle_texture; 
                    slime.state = .idling;
                }
                texture.* = slime.current_texture;
                slime.last_state = slime.state;
            }
        }
    }
};
