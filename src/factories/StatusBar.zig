const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const raylib = @import("raylib");
const comps = Prescient.compTypes;

pub var EnergyStatusBar = StatusBar{
    .position = .{.x = 10, .y = 750},
    .color = .yellow,
    .max_size = .{.width = 780, .height = 25},
    .status_bar = .{
        .status_type = .energy,
        .max_size = undefined,
        .current_size = undefined,
        .entity_link = undefined,
    },
};

pub const StatusBar = struct {
    position: comps.Position, 
    color: comps.Color,
    max_size: comps.Rectangle,
    status_bar: comps.StatusBar,

    pub fn spawn(self: *@This(), entity_link: Prescient.Entity) !Prescient.Entity{
        const prescient = try Prescient.getPrescient();
        var pool = try prescient.getPool(.GeneralPool);

        self.status_bar.max_size = self.max_size;
        self.status_bar.current_size = self.max_size;
        self.status_bar.entity_link = entity_link;

        return try pool.createEntity(.{
            .Position = self.position,
            .Color = self.color,
            .StatusBar = self.status_bar 
        });
    }
};
