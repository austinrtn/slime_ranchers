const Prescient = @import("../ecs/Prescient.zig").Prescient;

pub const Attack = struct {
    damage: f32, // damange dealt to others
    timeout: f32, //Time needed to attack again
    time_since_last_attack: f32 = 0.0, //Accumulated time since last attack 
    recovering: bool = false, //Can not attack because timeout
    can_attack: bool = true,
};
