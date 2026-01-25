//! Build tool access to registry enums only
//! This avoids importing actual component/system types which can cause circular dependencies

// Only export the enums, not the type maps or actual types
pub const SystemName = @import("registries/SystemRegistry.zig").SystemName;
pub const ComponentName = @import("registries/ComponentRegistry.zig").ComponentName;

// SystemDependencyGraph has its own internal imports of the full registries
pub const SystemDependencyGraph = @import("ecs/SystemDependencyGraph.zig");
