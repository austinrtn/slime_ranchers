const std = @import("std");
const EntityPool = @import("../ecs/EntityPool.zig").EntityPool;
const CR = @import("../registries/ComponentRegistry.zig");
const ComponentName = CR.ComponentName;
const general_components = std.meta.tags(CR.ComponentName);

pub const GeneralPool = EntityPool(.{
    .name = .GeneralPool,
    .components = general_components,
    .req = null,
    .storage_strategy = .SPARSE,
});
// benchmark test
// benchmark test
// benchmark test
// benchmark test
