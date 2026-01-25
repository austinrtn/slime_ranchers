const std = @import("std");
const EntityPool = @import("../ecs/EntityPool.zig").EntityPool;
const CR = @import("../registries/ComponentRegistry.zig");
const ComponentName = CR.ComponentName;

// Define which components this pool supports
const pool_components = &[_]ComponentName{
    .Attack,
    .Energy,
    .Controller,
    .AI,
};

const req_components = &[_]ComponentName{
    .Position,
    .Velocity,
    .BoundingBox,
    .Speed,
    .Sprite,
    .Texture,
    .Slime,
    .Health,
};

pub const SlimePool = EntityPool(.{
    .name = .SlimePool,
    .components = pool_components,
    .req = req_components,
    .storage_strategy = .ARCHETYPE,
});
