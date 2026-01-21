const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const Entity = Prescient.Entity;

pub const Test = struct {
    const Self = @This();

    prescient: *Prescient,

    pub fn init() !Self {
        return .{
            .prescient = try Prescient.getPrescient(),
        };
    }

    pub fn spawn(self: *Self) !Entity {
        const pool = try self.prescient.getPool(.GeneralPool);
        return try pool.createEntity(.{
              //Add components here:
              // .Position = .{.x = 0, .y = 0},
              // .Velocity = .{.dx = 1, .dy = 1},
        });
    }
};

