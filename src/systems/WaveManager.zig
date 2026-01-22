const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;
const raylib = @import("raylib");

pub const WaveManager = struct {
    const Self = @This();

    // Dependency declarations for compile-time system ordering
    pub const reads = [_]type{};
    pub const writes = [_]type{};

    allocator: std.mem.Allocator,
    active: bool = true,
    
    queries: struct {
        waves: Query(.{ .comps = &.{.Position, .SlimeRef, .Sprite, .Wave}}),
    },

    pub fn update(self: *Self) !void {
        var prescient = try Prescient.getPrescient();

        while(try self.queries.waves.next()) |b| {
            for(b.entities, b.Position, b.SlimeRef, b.Sprite, b.Wave) |ent, pos, ref, sprite, wave| {
                const slime = try prescient.ent.getEntityComponentData(ref.*, .Slime);
                const slime_pos = try prescient.ent.getEntityComponentData(ref.*, .Position);

                pos.* = slime_pos.*;

                if(slime.last_state == .attacking and slime.state != .attacking) { 
                    wave.active = true; 
                }

                wave.time_acc+= raylib.getFrameTime();
                if(wave.time_acc >= wave.anim_length) {
                    var pool = try prescient.getPool(.WavePool);
                    try pool.destroyEntity(ent);
                }

                const percent_acc = wave.time_acc / wave.anim_length;

                sprite.scale = wave.start_scale + (wave.end_scale * percent_acc);

                const min_alpha: f32 = 50.0;
                const alpha: u8 = 
                    @intFromFloat(255.0 - ((255.0 - min_alpha) * percent_acc));

                sprite.tint.a = alpha;

                sprite.is_visible = true;

                if(!wave.active) {
                    wave.time_acc = 0;
                    sprite.frame_index = 0;
                    sprite.delay_counter = 0;
                    sprite.is_visible = false;
                    sprite.tint.a = 255;
                    wave.opacity_acc = 255;
                }
            }
        }
    }
};
