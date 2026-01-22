const std = @import("std");
const EntityPool = @import("../ecs/EntityPool.zig").EntityPool;
const CR = @import("../registries/ComponentRegistry.zig");
const ComponentName = CR.ComponentName;

// Define which components this pool supports
const pool_components = &[_]ComponentName{
    .BoundingBox,
};

const req_components = &[_]ComponentName{
    .Position,
    .Texture,
    .SlimeRef,
    .Wave,
    .Sprite,
};

pub const WavePool = EntityPool(.{
    .name = .WavePool,
    .components = pool_components,
    .req = req_components,
    .storage_strategy = .SPARSE,
});
