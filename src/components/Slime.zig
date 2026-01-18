const Prescient = @import("../ecs/Prescient.zig").Prescient;
const raylib = @import("raylib");

pub const Slime = struct {
    const Self = @This();
    const SlimeType = enum {
        slime1,
        slime2,
        slime3,
    };

    pub const State = enum {
        idling,
        moving,
        attacking,
    };

    idle_path: [:0]const u8,
    moving_path: [:0]const u8,
    attack_path: [:0]const u8,

    current_texture: raylib.Texture2D = undefined,
    idle_texture: raylib.Texture2D = undefined,
    moving_texture: raylib.Texture2D = undefined,
    attack_texture: raylib.Texture2D = undefined,

    state: State = .idling,
    last_state: State = .idling,

    pub fn init(slime_type: SlimeType) !@This(){
        var slime: Self = undefined;
        switch(slime_type) {
            .slime1 => {
                slime = SlimeTypes.slime1; 
            },
            .slime2 => {
                slime = SlimeTypes.slime2; 
            },
            .slime3 => {
                slime = SlimeTypes.slime3; 
            },
        }
        try slime.load_textures();
        slime.current_texture = slime.idle_texture;
        return slime;
    }

    pub fn load_textures(self: *Self) !void {
        self.idle_texture = try raylib.loadTexture(self.idle_path);
        self.moving_texture = try raylib.loadTexture(self.moving_path);
        self.attack_texture = try raylib.loadTexture(self.attack_path);
    }

    pub fn getSprite(_: Self) Prescient.compTypes.Sprite {
        return Prescient.compTypes.Sprite.initFromSpriteSheet(64, 64, 6, 6, 180, 3);
    }
};
const Dirs = struct {
    const main_dir = "assets/main_slimes/PNG/";
    const slime1 = main_dir ++ "Slime1/Without_shadow/";
    const slime2 = main_dir ++ "Slime2/Without_shadow/";
    const slime3 = main_dir ++ "Slime3/Without_shadow/";
};

const SlimeTypes = struct {
    const slime1 = Slime{
        .idle_path = Dirs.slime1 ++ "Slime1_Idle_without_shadow.png",
        .moving_path = Dirs.slime1 ++ "Slime1_Walk_without_shadow.png",
        .attack_path = Dirs.slime1 ++ "Slime1_Attack_without_shadow.png",
    };
    const slime2 = Slime{
        .idle_path = Dirs.slime2 ++ "Slime2_Idle_without_shadow.png",
        .moving_path = Dirs.slime2 ++ "Slime2_Walk_without_shadow.png",
        .attack_path = Dirs.slime2 ++ "Slime2_Attack_without_shadow.png",
    };
    const slime3 = Slime{
        .idle_path = Dirs.slime3 ++ "Slime3_Idle_without_shadow.png",
        .moving_path = Dirs.slime3 ++ "Slime3_Walk_without_shadow.png",
        .attack_path = Dirs.slime3 ++ "Slime3_Attack_without_shadow.png",
    };
};

