const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const Entity = Prescient.Entity;
const CompTypes = Prescient.Components.Types;

pub const TextFactory = struct {
    const Self = @This();

    prescient: *Prescient,

    pub fn init() !Self {
        return .{
            .prescient = try Prescient.getPrescient(),
        };
    }

    pub fn spawn(self: *Self, pos: CompTypes.Position, color: CompTypes.Color, text_content: [:0]const u8, font_size: i32) !Entity {
        var pool = try self.prescient.getPool(.TextPool);
        return try pool.createEntity(.{
            .Position = pos,
            .Color = color,
            .Text = .{.content = text_content, .font_size = font_size},
        });
    }
};

