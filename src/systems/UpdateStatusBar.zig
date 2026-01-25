const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;
const Data = @import("../main.zig").getData;

pub const UpdateStatusBar = struct {
    const Self = @This();
    pub const enabled: bool = true;

    // Dependency declarations for compile-time system ordering
    pub const reads = [_]type{};
    pub const writes = [_]type{};

    allocator: std.mem.Allocator,
    active: bool = true,
    queries: struct {
        status_bars: Query(.{.read = &.{}, .write = &.{.StatusBar}}),
    },

    pub fn update(self: *Self) !void {
        const prescient = try Prescient.getPrescient();
        const ctx = struct {
            pub const prescient = prescient;
            pub const data = getData();
        };

        try self.queries.status_bars.forEach(ctx, struct{
            pub fn run(ctx: anytype, c: anytype) !bool {
                const status_bar = c.StatusBar;
                const prescient = data.prescient;
                const c:w
                var current_value: f32 = 0;
                var max_value: f32 = 0;

                if(status_bar.status_type == .energy) {
                    const energy_comp = try data.ent.getEntityComponentData(status_bar.entity_link, .Energy);
                    current_value = energy_comp.energy;
                    max_value = energy_comp.max_energy;
                } else if(status_bar.status_type == .health){
                    const health_comp = try data.ent.getEntityComponentData(status_bar.entity_link, .Health);
                    current_value = health_comp.health;
                    max_value = health_comp.max_health;
                } else if(status_bar.status == .loading) {
                    const m 
                }
                const percent = current_value / max_value;
                status_bar.current_size.width = status_bar.max_size.width * percent;
                return true;
            }
        });
    }
};
