const std = @import("std");
const System = @import("registries/SystemRegistry.zig").SystemName;
const Prescient = @import("ecs/Prescient.zig").Prescient;
const raylib = @import("raylib");

var prescient: *Prescient = undefined;
const Slime = Prescient.Factories.Slime{};
var player: Prescient.Entity = undefined;

var enemy_count: usize = 0;
const max_enemies: usize = 50;

pub const Data = struct {
    const Self = @This();
    pub var singleton: *Self = undefined;

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = .{};
        singleton = self;
        return self;
    }

    pub fn deinit(allocator: std.mem.Allocator) void {
        allocator.destroy(singleton); 
    }

    pub fn getData() *Data{
        return singleton;
    }

    sprites_loaded: usize = 0,
    total_sprites: usize = max_enemies,
};


pub fn main() !void {
    var health_bar = Prescient.Factories.StatusBar.HealthStatusBar;
    var energy_bar = Prescient.Factories.StatusBar.EnergyStatusBar;
    var loading_bar = Prescient.Factories.StatusBar.LoadingBar;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const data = try Data.init(allocator);
    defer Data.deinit(allocator);

    prescient = try Prescient.init(allocator);
    defer prescient.deinit();

    prescient.getSystem(.AIManager).active = false;
    prescient.getSystem(.Render).render_bounding_boxes = false;
    player = try Slime.spawnPlayer(.{.x = 400, .y = 400}, .slime1);
    try spawnEnemy(max_enemies);

    const load_bar = try loading_bar.spawn(player);
    _ = try health_bar.spawn(player);
    _ = try energy_bar.spawn(player);

    var initing: bool = true;
    while(!raylib.windowShouldClose()) {
        try prescient.update();
        if(initing) {
            try spawnEnemy(1);
            data.sprites_loaded += 1;
            if(data.sprites_loaded == data.total_sprites) {
                prescient.ent.destroy(load_bar) catch {
                };
                prescient.getSystem(.AIManager).active = true;
                initing = false;
            }         
        }
    }
}

pub fn spawnEnemy(ent_count: usize) !void {
    for(0..ent_count) |_| {
        const x: f32 = blk: {
            const x_val = raylib.getRandomValue(-200,1000);
            break :blk @floatFromInt(x_val);
        };
        const y: f32 = blk: {
            const left_half = if(raylib.getRandomValue(0,1) == 0) true else false; 
            const y_val = if(left_half) raylib.getRandomValue(-250, -50) else raylib.getRandomValue(850, 1000);
            break :blk @floatFromInt(y_val);
        };

        _ = try Slime.spawnEnemy(.{.x = x, .y = y}, .slime2, player); 
    }
}
