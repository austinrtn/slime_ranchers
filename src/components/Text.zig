// Import only what you need to avoid circular dependencies
// const Entity = @import("../ecs/EntityManager.zig").Entity;

pub const Text = struct {
    content: [:0]const u8,
    font_size: i32,
};
