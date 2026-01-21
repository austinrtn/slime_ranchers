const Prescient = @import("../ecs/Prescient.zig").Prescient;

pub const Wave = struct {
    active: bool = false,

    anim_length: f32 = 0.25,
    time_acc: f32 = 0,
    
    start_scale: f32 = 1,
    end_scale: f32 = 3,

    opacity_acc: f32 = 255,
};
