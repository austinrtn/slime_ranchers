const std = @import("std");
const pr = @import("PoolRegistry.zig");

pub const FactoryName = enum(u32) {
    PlayerSlime,
    ProtectionShield,
    StatusBar,
    Test,
};

pub const PlayerSlime = @import("../factories/player_slime.zig").PlayerSlime;
pub const ProtectionShield = @import("../factories/ProtectionShield.zig").ProtectionShield;
pub const StatusBar = @import("../factories/StatusBar.zig").StatusBar;
pub const Test = @import("../factories/Test.zig").Test;

pub const factoryTypes = struct {
    pub const PlayerSlime = @import("../factories/player_slime.zig").PlayerSlime;
    pub const ProtectionShield = @import("../factories/ProtectionShield.zig").ProtectionShield;
    pub const StatusBar = @import("../factories/StatusBar.zig").StatusBar;
    pub const Test = @import("../factories/Test.zig").Test;
};

pub const factory_types = [_]type{
    PlayerSlime,
    ProtectionShield,
    StatusBar,
    Test,
};

pub fn getFactoryFromName(comptime factory: FactoryName) type {
    return factory_types[@intFromEnum(factory)];
}
