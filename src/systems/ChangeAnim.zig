const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;
const raylib = @import("raylib");

pub const ChangeAnim = struct {
    const Self = @This();
    pub const enabled: bool = true;
    pub const runs_before = &.{ .Animate, .Collision };

    allocator: std.mem.Allocator,
    active: bool = true,
    queries: struct {
        slimes: Query(.{.read = &.{}, .write = &.{.Sprite, .Texture, .BoundingBox, .Slime}}),
    },

    pub fn update(self: *Self) !void {
        try self.queries.slimes.forEach(null, struct{
            pub fn run(_: anytype, c: anytype) !bool {
                const slime = c.Slime;
                const texture = c.Texture;
                const sprite = c.Sprite;
                const bbox = c.BoundingBox;

                if(slime.state == slime.last_state) return true;

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
                return true;
            }
        });
    }
};
