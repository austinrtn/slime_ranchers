const raylib = @import("raylib");
const std = @import("std");

// Texture cache to avoid loading the same textures multiple times
const TextureCache = struct {
    idle_texture: ?raylib.Texture2D = null,
    moving_texture: ?raylib.Texture2D = null,
    attack_texture: ?raylib.Texture2D = null,
    loaded: bool = false,
};

// Module-level texture caches for each slime type
var slime1_cache: TextureCache = .{};
var slime2_cache: TextureCache = .{};
var slime3_cache: TextureCache = .{};

pub const Slime = struct {
    const Self = @This();
    pub const SlimeType = enum {
        slime1,
        slime2,
        slime3,
    };

    pub const State = enum {
        idling,
        moving,
        attacking,
        recovering,
    };

    is_alive: bool = true,
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
                try ensureTexturesLoaded(&slime1_cache, slime.idle_path, slime.moving_path, slime.attack_path);
                slime.idle_texture = slime1_cache.idle_texture.?;
                slime.moving_texture = slime1_cache.moving_texture.?;
                slime.attack_texture = slime1_cache.attack_texture.?;
            },
            .slime2 => {
                slime = SlimeTypes.slime2;
                try ensureTexturesLoaded(&slime2_cache, slime.idle_path, slime.moving_path, slime.attack_path);
                slime.idle_texture = slime2_cache.idle_texture.?;
                slime.moving_texture = slime2_cache.moving_texture.?;
                slime.attack_texture = slime2_cache.attack_texture.?;
            },
            .slime3 => {
                slime = SlimeTypes.slime3;
                try ensureTexturesLoaded(&slime3_cache, slime.idle_path, slime.moving_path, slime.attack_path);
                slime.idle_texture = slime3_cache.idle_texture.?;
                slime.moving_texture = slime3_cache.moving_texture.?;
                slime.attack_texture = slime3_cache.attack_texture.?;
            },
        }
        slime.current_texture = slime.idle_texture;
        return slime;
    }

    fn ensureTexturesLoaded(cache: *TextureCache, idle_path: [:0]const u8, moving_path: [:0]const u8, attack_path: [:0]const u8) !void {
        if (!cache.loaded) {
            std.debug.print("Loading slime textures: {s}\n", .{idle_path});
            cache.idle_texture = try raylib.loadTexture(idle_path);
            cache.moving_texture = try raylib.loadTexture(moving_path);
            cache.attack_texture = try raylib.loadTexture(attack_path);
            cache.loaded = true;
        }
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

