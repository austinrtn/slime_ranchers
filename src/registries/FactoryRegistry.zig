const std = @import("std");
const pr = @import("PoolRegistry.zig");

pub const FactoryName = enum(u32) {
    ProtectionShield,
    Slime,
    StatusBar,
    Test,
    TextFactory,
    WaveFactory,
};

pub const ProtectionShield = @import("../factories/ProtectionShield.zig").ProtectionShield;
pub const Slime = @import("../factories/SlimeFactory.zig").Slime;
pub const StatusBar = @import("../factories/StatusBar.zig").StatusBar;
pub const Test = @import("../factories/Test.zig").Test;
pub const TextFactory = @import("../factories/TextFactory.zig").TextFactory;
pub const WaveFactory = @import("../factories/WaveFactory.zig").WaveFactory;

pub const factoryTypes = struct {
    pub const ProtectionShield = @import("../factories/ProtectionShield.zig").ProtectionShield;
    pub const Slime = @import("../factories/SlimeFactory.zig").Slime;
    pub const StatusBar = @import("../factories/StatusBar.zig").StatusBar;
    pub const Test = @import("../factories/Test.zig").Test;
    pub const TextFactory = @import("../factories/TextFactory.zig").TextFactory;
    pub const WaveFactory = @import("../factories/WaveFactory.zig").WaveFactory;
};

pub const factory_types = [_]type{
    ProtectionShield,
    Slime,
    StatusBar,
    Test,
    TextFactory,
    WaveFactory,
};

pub fn getFactoryFromName(comptime factory: FactoryName) type {
    return factory_types[@intFromEnum(factory)];
}
