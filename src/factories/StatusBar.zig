const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const raylib = @import("raylib");
const comps = Prescient.Components.Types;

pub const StatusBar = struct {
    pub var EnergyStatusBar = StatusBar{
        .position = .{.x = 10, .y = 770},
        .color = .yellow,
        .max_size = .{.width = 780, .height = 25},
        .status_bar = .{
            .status_type = .energy,
            .max_size = undefined,
            .current_size = undefined,
            .entity_link = undefined,
        },
    };

    pub var HealthStatusBar = StatusBar {
        .position = .{.x = 10, .y = 740},
        .color = .red,
        .max_size = .{.width = 780, .height = 25},
        .status_bar = .{
            .status_type = .health,
            .max_size = undefined,
            .current_size = undefined,
            .entity_link = undefined,
        }
    };

    const width =  200;
    const height = 50;

    pub var LoadingBar = StatusBar {
        .position = .{ . x = 400 - (width/2), .y = 400 - (height/2)}, 
        .color = .black,
        .max_size = .{.width = width, .height = height},
        .status_bar = .{
            .status_type = .loading,
            .max_size = undefined,
            .current_size = undefined,
            .entity_link = undefined, 
        },
    };

    position: comps.Position, 
    color: comps.Color,
    max_size: comps.Rectangle,
    status_bar: comps.StatusBar,

    pub fn spawn(self: *@This(), entity_link: Prescient.Entity) !Prescient.Entity{
        const prescient = try Prescient.getPrescient();
        var pool = try prescient.getPool(.StatusBar);

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
