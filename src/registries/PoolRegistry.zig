const std = @import("std");
const cr = @import("ComponentRegistry.zig");
const EntityPool = @import("../ecs/EntityPool.zig").EntityPool;
const StorageStrategy = @import("../ecs/StorageStrategy.zig").StorageStrategy;

pub const PoolName = enum(u32) {
    GeneralPool,
    SlimePool,
    StatusBar,
    WavePool,
};

pub const GeneralPool = @import("../pools/GeneralPool.zig").GeneralPool;
pub const SlimePool = @import("../pools/SlimePool.zig").SlimePool;
pub const StatusBar = @import("../pools/StatusBar.zig").StatusBar;
pub const WavePool = @import("../pools/WavePool.zig").WavePool;

pub const PoolTypeMap = struct {
    pub const GeneralPool = @import("../pools/GeneralPool.zig").GeneralPool;
    pub const SlimePool = @import("../pools/SlimePool.zig").SlimePool;
    pub const StatusBar = @import("../pools/StatusBar.zig").StatusBar;
    pub const WavePool = @import("../pools/WavePool.zig").WavePool;
};

pub const pool_types = [_]type{
    GeneralPool,
    SlimePool,
    StatusBar,
    WavePool,
};

pub fn getPoolFromName(comptime pool: PoolName) type {
    return pool_types[@intFromEnum(pool)];
}

/// Check at compile time if a pool contains a specific component
pub fn poolHasComponent(comptime pool_name: PoolName, comptime component: cr.ComponentName) bool {
    const PoolType = getPoolFromName(pool_name);
    const pool_components = PoolType.COMPONENTS;

    for (pool_components) |comp| {
        if (comp == component) {
            return true;
        }
    }
    return false;
}

pub const PoolConfig = struct {
    name: PoolName,
    req: ?[]const cr.ComponentName = null,
    components: ?[]const cr.ComponentName = null,
    storage_strategy: StorageStrategy,
};
