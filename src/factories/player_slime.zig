const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const raylib = @import("raylib");
const comps = Prescient.compTypes;

pub const PlayerSlime = struct {
    //defaults
    velocity: comps.Velocity = .{.dx = 0, .dy = 0},
    energy: comps.Energy = .{.energy = 100, .max_energy = 100, .movement_cost = 10, .regen_per_frame = 15},
    slime_type:  comps.Slime.SlimeType = comps.Slime.SlimeType.slime2,
    speed: f32 = 60,

    sprite_width: f32 = 64,
    sprite_height: f32 = 64,
    sprite_cols: u32 = 6,
    sprite_rows: u32 = 6,
    sprite_frame_delay: u32 = 180,
    sprite_frames: f32 = 3,
    
    pub fn spawn(
        self: @This(),
        pos: comps.Position,
    ) !Prescient.Entity {
        const prescient = try Prescient.getPrescient(); 

        var pool = try prescient.getPool(.GeneralPool);
        const slime = try comps.Slime.init(self.slime_type);

        return try pool.createEntity(.{
            .Position = pos,
            .Velocity = self.velocity,

            .Slime = slime,
            .Texture = slime.current_texture,
            .Sprite = comps.Sprite.initFromSpriteSheet(
                self.sprite_width, 
                self.sprite_height, 
                self.sprite_cols, 
                self.sprite_rows, 
                self.sprite_frame_delay, 
                self.sprite_frames
            ),
            .Speed = self.speed,
            .Controller = .{},
            .Energy = self.energy,
        });
    }
};
