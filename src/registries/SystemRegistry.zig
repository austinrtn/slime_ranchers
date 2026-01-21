const std = @import("std");

pub const Animate = @import("../systems/Animate.zig").Animate;
pub const Attack = @import("../systems/Attack.zig").Attack;
pub const ChangeAnim = @import("../systems/ChangeAnim.zig").ChangeAnim;
pub const Collision = @import("../systems/Collision.zig").Collision;
pub const Controller = @import("../systems/Controller.zig").Controller;
pub const EnergyManager = @import("../systems/EnergyManager.zig").EnergyManager;
pub const Movement = @import("../systems/Movement.zig").Movement;
pub const Render = @import("../systems/Render.zig").Render;
pub const Track = @import("../systems/Track.zig").Track;
pub const UpdateStatusBar = @import("../systems/UpdateStatusBar.zig").UpdateStatusBar;
pub const WaveManager = @import("../systems/WaveManager.zig").WaveManager;

pub const SystemTypeMap = struct {
    pub const Animate = @import("../systems/Animate.zig").Animate;
    pub const Attack = @import("../systems/Attack.zig").Attack;
    pub const ChangeAnim = @import("../systems/ChangeAnim.zig").ChangeAnim;
    pub const Collision = @import("../systems/Collision.zig").Collision;
    pub const Controller = @import("../systems/Controller.zig").Controller;
    pub const EnergyManager = @import("../systems/EnergyManager.zig").EnergyManager;
    pub const Movement = @import("../systems/Movement.zig").Movement;
    pub const Render = @import("../systems/Render.zig").Render;
    pub const Track = @import("../systems/Track.zig").Track;
    pub const UpdateStatusBar = @import("../systems/UpdateStatusBar.zig").UpdateStatusBar;
    pub const WaveManager = @import("../systems/WaveManager.zig").WaveManager;
};

pub const SystemName = enum {
    Animate,
    Attack,
    ChangeAnim,
    Collision,
    Controller,
    EnergyManager,
    Movement,
    Render,
    Track,
    UpdateStatusBar,
    WaveManager,
};

pub const SystemTypes = [_]type {
    Animate,
    Attack,
    ChangeAnim,
    Collision,
    Controller,
    EnergyManager,
    Movement,
    Render,
    Track,
    UpdateStatusBar,
    WaveManager,
};

pub fn getTypeByName(comptime system_name: SystemName) type {
    const index = @intFromEnum(system_name);
    return SystemTypes[index];
}
