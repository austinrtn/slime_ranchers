const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;
const raylib = @import("raylib");
const Phase = @import("../registries/Phases.zig").Phase;

pub const WaveManager = struct {
    const Self = @This();
    pub const enabled: bool = true;
    pub const phase: Phase = .PreUpdate;
    pub const runs_before = &.{.Movement, .Animate, .ChangeAnim, .Render};

    // Dependency declarations for compile-time system ordering
    pub const reads = [_]type{};
    pub const writes = [_]type{};

    allocator: std.mem.Allocator,
    active: bool = true,
    
    queries: struct {
        waves: Query(.{.read = &.{.SlimeRef}, .write = &.{.Position, .Sprite, .Wave}}),
    },

    pub fn update(self: *Self) !void {
        const prescient = try Prescient.getPrescient();

        try self.queries.waves.forEach(prescient, struct{
            pub fn run(data: anytype, c: anytype) !bool {
                const ent = c.entity;
                const pos = c.Position;
                const ref = c.SlimeRef;
                const sprite = c.Sprite;
                const wave = c.Wave;

                const slime = try data.ent.getComponent(ref.*, .Slime);
                const slime_pos = try data.ent.getComponent(ref.*, .Position);

                pos.* = slime_pos.*;

                if(slime.last_state == .attacking and slime.state != .attacking) {
                    wave.active = true;
                }

                wave.time_acc+= raylib.getFrameTime();
                if(wave.time_acc >= wave.anim_length) {
                    var pool = try data.getPool(.WavePool);
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
                return true;
            }
        });
    }
};
