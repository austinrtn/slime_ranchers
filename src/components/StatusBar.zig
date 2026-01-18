const Prescient = @import("../ecs/Prescient.zig").Prescient;

pub const StatusBar = struct {
    pub const StatusType = enum {
        health,
        energy
    };
    status_type: StatusType,
    entity_link: Prescient.Entity,

    current_size: Prescient.compTypes.Rectangle,
    max_size: Prescient.compTypes.Rectangle,
};
