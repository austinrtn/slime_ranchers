const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const raylib = @import("raylib");
const comps = Prescient.compTypes;

pub const Slime = struct {
    //defaults
    velocity: comps.Velocity = .{.dx = 0, .dy = 0},
    health: Prescient.compTypes.Health = .{.health = 50, .max_health = 100},
    energy: comps.Energy = .{
        .energy = 100, 
        .max_energy = 100, 
        .movement_cost = 10, 
        .regen_per_frame = 8,
        .attack_cost = 15,
        .min_req = 20,
    },
    attack: comps.Attack = .{
        .damage = 10,
        .timeout = 0.5,
    },

    slime_type:  comps.Slime.SlimeType = comps.Slime.SlimeType.slime2,
    speed: f32 = 60,

    sprite_width: f32 = 64,
    sprite_height: f32 = 64,
    sprite_cols: u32 = 6,
    sprite_rows: u32 = 6,
    sprite_frame_delay: f32 = 0.1, // Seconds between animation frames
    sprite_frames: f32 = 3,
    sprite_tint: raylib.Color = .white, 
    scale: f32 = 3,


    pub fn spawnPlayer(
        self: @This(),
        pos: comps.Position,
        slime_type: comps.Slime.SlimeType,
    ) !Prescient.Entity {
        const prescient = try Prescient.getPrescient(); 
        var pool = try prescient.getPool(.SlimePool);
        const slime = try comps.Slime.init(slime_type);

        return try pool.createEntity(.{
            .Position = pos,
            .Velocity = self.velocity,

            .Slime = slime,
            .Texture = slime.current_texture,
            .Sprite = comps.Sprite.initFromSpriteSheet(
                self.sprite_width,
                self.sprite_height,
                self.sprite_cols,
                @intFromFloat(self.sprite_frames),
                self.sprite_frame_delay,
                self.scale,
            ),
            .Speed = self.speed,
            .Controller = .{},
            .Energy = self.energy,
            .Attack = self.attack,
            .Health = self.health,
            .BoundingBox = .{ .width = 18, .height = 16 }, 
        });
    }

    pub fn spawnEnemy(
        self: @This(),
        pos: comps.Position,
        slime_type: comps.Slime.SlimeType,
    ) !Prescient.Entity {
        const prescient = try Prescient.getPrescient(); 
        var pool = try prescient.getPool(.SlimePool);
        const slime = try comps.Slime.init(slime_type);

        return try pool.createEntity(.{
            .Position = pos,
            .Velocity = self.velocity,

            .Slime = slime,
            .Texture = slime.current_texture,
            .Sprite = comps.Sprite.initFromSpriteSheet(
                self.sprite_width,
                self.sprite_height,
                self.sprite_cols,
                @intFromFloat(self.sprite_frames),
                self.sprite_frame_delay,
                self.scale,
            ),
            .Attack = self.attack,
            .Speed = self.speed,
            .BoundingBox = .{ .width = 18, .height = 16 }, 
            .Health = self.health,
        });
    }
};
