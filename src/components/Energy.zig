const Prescient = @import("../ecs/Prescient.zig").Prescient;

pub const Energy = struct {
    energy: f32,
    max_energy: f32,
    movement_cost: f32, 
    regen_per_frame: f32,
};
