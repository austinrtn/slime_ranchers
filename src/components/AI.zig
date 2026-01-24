const Prescient = @import("../ecs/Prescient.zig").Prescient;
const Entity = Prescient.Entity;

pub const AI = struct {
    pub const State = enum {
        TARGETING_ENTITY,
    };

    state: State = .TARGETING_ENTITY,
    ent_ref: Entity, 
};
