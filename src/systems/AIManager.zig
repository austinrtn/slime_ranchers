const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const SR = @import("../registries/SystemRegistry.zig");
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;
const raylib = @import("raylib");

pub const AIManager = struct {
    const Self = @This();
    pub const enabled: bool = true;

    // Optional: resolve write-write conflicts with other systems
    pub const runs_before = &[_]SR.SystemName{ .Movement};
    pub const runs_after = &[_]SR.SystemName{ .WaveManager};

    allocator: std.mem.Allocator,
    prescient: *Prescient = undefined,
    active: bool = true,
    queries: struct {
        slimes: Query(.{
            .read = &.{.Position, .Speed},  
            .write = &.{.AI, .Velocity}, 
        }),
    },

    pub fn init(self: *Self) !void {
        self.prescient = try Prescient.getPrescient();
    }

    pub fn update(self: *Self) !void {
        try self.queries.slimes.forEach(self, struct {
            pub fn run(ctx: anytype, c: anytype) !bool {

                const pos = c.Position;
                const vel = c.Velocity;
                const ai: Prescient.Components.Types.AI = c.AI.*;

                if(ai.state == .TARGETING_ENTITY) {
                    const pos_vect = raylib.Vector2{.x = pos.x, .y = pos.y};
                    const target_pos = try ctx.prescient.ent.getEntityComponentData(ai.ent_ref, .Position);
                    const target_vect= raylib.Vector2{.x = target_pos.x, .y = target_pos.y};
                    const dist = raylib.Vector2.subtract(target_vect, pos_vect);
                    const length = raylib.Vector2.length(dist);
                    _ = length;

                    const new_vel = raylib.Vector2.scale(raylib.Vector2.normalize(dist), c.Speed.*);
                    vel.dx = new_vel.x;
                    vel.dy = new_vel.y;
                }
                return true;  // continue (return false to stop iteration)
            }
        });
    }

};
