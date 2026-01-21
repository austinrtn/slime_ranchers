const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const Entity = Prescient.Entity;
const raylib = @import("raylib");

const comp_types = Prescient.Components.Types;

pub const WaveFactory = struct {
    const Self = @This();

    prescient: *Prescient,
    asset: [:0]const u8 = "assets/pixel_effects/17_felspell_spritesheet.png",
    texture: raylib.Texture2D = undefined, 
    
    sprite_width: f32 = 100,
    sprite_height: f32 = 100,
    sprite_cols: u32 = 10,
    sprite_rows: u32 = 10,
    sprite_frame_delay: f32 = 0.1, // Seconds between animation frames
    sprite_frames: f32 = 3,
    sprite_tint: raylib.Color = .white, 
    scale: f32 = 3,

    pub fn init() !Self {
        var self = Self{.prescient = try Prescient.getPrescient()};
        self.texture = try raylib.loadTexture(self.asset);
        return self;
    }

    pub fn spawn(self: *Self, args: struct {
        position: comp_types.Position,
        slime_ref: comp_types.SlimeRef,
    }) !Entity {
        var sprite = comp_types.Sprite.initFromSpriteSheet(
            self.sprite_width, 
            self.sprite_height, 
            self.sprite_cols, 
            @intFromFloat(self.sprite_frames), 
            self.sprite_frame_delay, 
            self.scale
        );
        
        sprite.animation_mode = .once;

        var pool = try self.prescient.getPool(.WavePool);
        return try pool.createEntity(.{
            .Position = args.position, 
            .SlimeRef = args.slime_ref,
            .Sprite = sprite,
            .Texture = self.texture,
            .Wave = .{},
            .BoundingBox = .{},
        });
    }
};

