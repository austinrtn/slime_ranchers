const std = @import("std");

pub const Attack = @import("../components/Attack.zig").Attack;
pub const Circle = @import("../components/Circle.zig").Circle;
pub const Collidable = @import("../components/Collidable.zig").Collidable;
pub const Color = @import("../components/Color.zig").Color;
pub const Controller = @import("../components/Controller.zig").Controller;
pub const Energy = @import("../components/Energy.zig").Energy;
pub const Health = @import("../components/Health.zig").Health;
pub const Position = @import("../components/Position.zig").Position;
pub const Rectangle = @import("../components/Rectangle.zig").Rectangle;
pub const Slime = @import("../components/Slime.zig").Slime;
pub const Speed = @import("../components/Speed.zig").Speed;
pub const Sprite = @import("../components/Sprite.zig").Sprite;
pub const StatusBar = @import("../components/StatusBar.zig").StatusBar;
pub const Texture = @import("../components/Texture.zig").Texture;
pub const Velocity = @import("../components/Velocity.zig").Velocity;

pub const compTypes = struct {
    pub const Attack = @import("../components/Attack.zig").Attack;
    pub const Circle = @import("../components/Circle.zig").Circle;
    pub const Collidable = @import("../components/Collidable.zig").Collidable;
    pub const Color = @import("../components/Color.zig").Color;
    pub const Controller = @import("../components/Controller.zig").Controller;
    pub const Energy = @import("../components/Energy.zig").Energy;
    pub const Health = @import("../components/Health.zig").Health;
    pub const Position = @import("../components/Position.zig").Position;
    pub const Rectangle = @import("../components/Rectangle.zig").Rectangle;
    pub const Slime = @import("../components/Slime.zig").Slime;
    pub const Speed = @import("../components/Speed.zig").Speed;
    pub const Sprite = @import("../components/Sprite.zig").Sprite;
    pub const StatusBar = @import("../components/StatusBar.zig").StatusBar;
    pub const Texture = @import("../components/Texture.zig").Texture;
    pub const Velocity = @import("../components/Velocity.zig").Velocity;
};

pub const ComponentName = enum {
    Attack,
    Circle,
    Collidable,
    Color,
    Controller,
    Energy,
    Health,
    Position,
    Rectangle,
    Slime,
    Speed,
    Sprite,
    StatusBar,
    Texture,
    Velocity,
};

pub const ComponentTypes = [_]type {
    Attack,
    Circle,
    Collidable,
    Color,
    Controller,
    Energy,
    Health,
    Position,
    Rectangle,
    Slime,
    Speed,
    Sprite,
    StatusBar,
    Texture,
    Velocity,
};

pub fn getTypeByName(comptime component_name: ComponentName) type {
    const index = @intFromEnum(component_name);
    return ComponentTypes[index];
}
