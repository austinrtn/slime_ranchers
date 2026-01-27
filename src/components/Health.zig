pub const Health = struct {
    health: f32,
    max_health: f32,

    time_acc: f32 = 0,
    time_invincible: f32 = 1.5,

    queue_damage: bool = false,
    taking_damange: bool = false,
};
