const std = @import("std");

pub const Circle = @import("../components/Circle.zig").Circle;
pub const Controller = @import("../components/Controller.zig").Controller;
pub const Energy = @import("../components/Energy.zig").Energy;
pub const Position = @import("../components/Position.zig").Position;
pub const Slime = @import("../components/Slime.zig").Slime;
pub const Speed = @import("../components/Speed.zig").Speed;
pub const Sprite = @import("../components/Sprite.zig").Sprite;
pub const Texture = @import("../components/Texture.zig").Texture;
pub const Velocity = @import("../components/Velocity.zig").Velocity;

pub const compTypes = struct {
    pub const Circle = @import("../components/Circle.zig").Circle;
    pub const Controller = @import("../components/Controller.zig").Controller;
    pub const Energy = @import("../components/Energy.zig").Energy;
    pub const Position = @import("../components/Position.zig").Position;
    pub const Slime = @import("../components/Slime.zig").Slime;
    pub const Speed = @import("../components/Speed.zig").Speed;
    pub const Sprite = @import("../components/Sprite.zig").Sprite;
    pub const Texture = @import("../components/Texture.zig").Texture;
    pub const Velocity = @import("../components/Velocity.zig").Velocity;
};

pub const ComponentName = enum {
    Circle,
    Controller,
    Energy,
    Position,
    Slime,
    Speed,
    Sprite,
    Texture,
    Velocity,
};

pub const ComponentTypes = [_]type {
    Circle,
    Controller,
    Energy,
    Position,
    Slime,
    Speed,
    Sprite,
    Texture,
    Velocity,
};

pub fn getTypeByName(comptime component_name: ComponentName) type {
    const index = @intFromEnum(component_name);
    return ComponentTypes[index];
}
