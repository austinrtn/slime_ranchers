const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;
const Data = @import("../main.zig").Data;

pub const UpdateStatusBar = struct {
    const Self = @This();
    pub const enabled: bool = true;

    allocator: std.mem.Allocator,
    active: bool = true,
    prescient: *Prescient = undefined,

    queries: struct {
        status_bars: Query(.{.read = &.{}, .write = &.{.StatusBar}}),
    },

    pub fn init(self: *Self) !void {
        self.prescient = try Prescient.getPrescient();
    }

    pub fn update(self: *Self) !void {
        try self.queries.status_bars.forEach(self, struct{
            pub fn run(ctx: anytype, c: anytype) !bool {
                const status_bar = c.StatusBar;
                const ecs = ctx.prescient;
                const data = ctx.prescient.getGlobalCtx();

                var current_value: f32 = 0;
                var max_value: f32 = 0;

                if(status_bar.status_type == .energy) {
                    const energy_comp = try ecs.ent.getComponent(status_bar.entity_link, .Energy);
                    current_value = energy_comp.energy;
                    max_value = energy_comp.max_energy;
                } else if(status_bar.status_type == .health){
                    const health_comp = try ecs.ent.getComponent(status_bar.entity_link, .Health);
                    current_value = health_comp.health;
                    max_value = health_comp.max_health;
                } else if(status_bar.status_type == .loading) {
                    current_value = @floatFromInt(data.sprites_loaded); 
                    max_value = @floatFromInt(data.total_sprites);
                }
                const percent: f32 = current_value / max_value;
                status_bar.current_size.width = status_bar.max_size.width * percent;

                return true;
            }
        });
    }
};
