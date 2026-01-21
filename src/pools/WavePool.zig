const std = @import("std");
const EntityPool = @import("../ecs/EntityPool.zig").EntityPool;
const CR = @import("../registries/ComponentRegistry.zig");
const ComponentName = CR.ComponentName;

// Define which components this pool supports
const pool_components = &[_]ComponentName{
    .Sprite,
};

const req_components = &[_]ComponentName{
    .Position,
//    .BoundingBox,
    .Texture,
    .SlimeRef,
    .Wave,
};

pub const WavePool = EntityPool(.{
    .name = .WavePool,
    .components = pool_components,
    .req = req_components,
    .storage_strategy = .SPARSE,
});
