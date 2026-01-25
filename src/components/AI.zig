const Entity = @import("../ecs/EntityManager.zig").Entity;

pub const AI = struct {
    pub const State = enum {
        TARGETING_ENTITY,
    };

    state: State = .TARGETING_ENTITY,
    ent_ref: Entity, 
};
