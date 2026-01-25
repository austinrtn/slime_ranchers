const Entity = @import("../ecs/EntityManager.zig").Entity;
const Rectangle = @import("Rectangle.zig").Rectangle;

pub const StatusBar = struct {
    pub const StatusType = enum {
        health,
        energy,
        loading,
    };
    status_type: StatusType,
    entity_link: Entity,

    current_size: Rectangle,
    max_size: Rectangle,
};
