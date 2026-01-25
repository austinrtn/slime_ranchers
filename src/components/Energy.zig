
pub const Energy = struct {
    energy: f32,
    max_energy: f32,
    movement_cost: f32, 
    attack_cost: f32,
    attack_reducted: bool = false,
    regen_per_frame: f32,

    min_req: f32,
};
