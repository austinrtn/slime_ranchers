const std = @import("std");

pub const Animate = @import("../systems/Animate.zig").Animate;
pub const ChangeAnim = @import("../systems/ChangeAnim.zig").ChangeAnim;
pub const Controller = @import("../systems/Controller.zig").Controller;
pub const EnergyManager = @import("../systems/EnergyManager.zig").EnergyManager;
pub const Movement = @import("../systems/Movement.zig").Movement;
pub const Render = @import("../systems/Render.zig").Render;
pub const Track = @import("../systems/Track.zig").Track;
pub const UpdateStatusBar = @import("../systems/UpdateStatusBar.zig").UpdateStatusBar;

pub const SystemName = enum {
    Animate,
    ChangeAnim,
    Controller,
    EnergyManager,
    Movement,
    Render,
    Track,
    UpdateStatusBar,
};

pub const SystemTypes = [_]type {
    Animate,
    ChangeAnim,
    Controller,
    EnergyManager,
    Movement,
    Render,
    Track,
    UpdateStatusBar,
};

pub fn getTypeByName(comptime system_name: SystemName) type {
    const index = @intFromEnum(system_name);
    return SystemTypes[index];
}
