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
        slimes: Query(.{ .comps = &.{.Slime, .Texture, .Sprite, .BoundingBox} }),
    },

    pub fn update(self: *Self) !void {
        while(try self.queries.slimes.next()) |b| {
            for(b.Slime, b.Texture, b.Sprite, b.BoundingBox) |slime, texture, sprite, bbox| {
                if(slime.state == slime.last_state) continue;

                sprite.frame_index = 0;
                sprite.delay_counter = 0;
                sprite.animation_complete = false;

                if(slime.state == .recovering) {
                    slime.current_texture = slime.idle_texture;
                    sprite.tint = raylib.Color.gray;
                    sprite.animation_mode = .looping;
                } else {
                    sprite.tint = raylib.Color.white;
                }

                if(slime.state == .attacking) {
                    slime.current_texture = slime.attack_texture;
                    sprite.animation_mode = .once;
                }
                else if(slime.state == .moving) {
                    slime.current_texture = slime.moving_texture;
                    sprite.animation_mode = .looping;
                    bbox.height = 18;
                }
                else if(slime.state == .idling){
                    slime.current_texture = slime.idle_texture;
                    sprite.animation_mode = .looping;
                    bbox.height = 16;
                }
                texture.* = slime.current_texture;
                slime.last_state = slime.state;
            }
        }
    }
};
