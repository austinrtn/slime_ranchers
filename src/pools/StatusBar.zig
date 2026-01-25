const std = @import("std");
const EntityPool = @import("../ecs/EntityPool.zig").EntityPool;
const CR = @import("../registries/ComponentRegistry.zig");
const ComponentName = CR.ComponentName;

// Define which components this pool supports
const pool_components = &[_]ComponentName{
};

const req_components = &[_]ComponentName{
    .Position,
    .Color,
    .StatusBar,
};

pub const StatusBar = EntityPool(.{
    .name = .StatusBar,
    .components = pool_components,
    .req = req_components,
    .storage_strategy = .ARCHETYPE,
});
