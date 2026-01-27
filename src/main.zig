const std = @import("std");
const System = @import("registries/SystemRegistry.zig").SystemName;
const Prescient = @import("ecs/Prescient.zig").Prescient;
const raylib = @import("raylib");

var prescient: *Prescient = undefined;
const Slime = Prescient.Factories.Slime{};
var player: Prescient.Entity = undefined;

var enemy_count: usize = 0;
const max_enemies: usize = 100;

pub const GlobalCtx = struct {
    pub const Self = @This();
    pub const WIDTH: i32 = 800;
    pub const HEIGHT: i32 = 800;

    pub fn init() !Self {
        return .{
            .width_f32 = @floatFromInt(WIDTH),
            .height_f32 = @floatFromInt(HEIGHT),
        };
    }

    width: i32 = WIDTH,
    height: i32 = HEIGHT,
    width_f32: f32,
    height_f32: f32,

    player_id: Prescient.Entity = undefined,

    sprites_loaded: usize = 0,
    total_sprites: usize = 0,
    dead_slimes: usize = 0,
};

pub fn main() !void {
    var health_bar = Prescient.Factories.StatusBar.HealthStatusBar;
    var energy_bar = Prescient.Factories.StatusBar.EnergyStatusBar;
    var loading_bar = Prescient.Factories.StatusBar.LoadingBar;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    prescient = try Prescient.init(allocator);
    defer prescient.deinit();

    const ctx = prescient.getGlobalCtx();
    
    var text_factory = try Prescient.Factories.TextFactory.init();
    try prescient.setSystemActive(.AIManager, false);

    prescient.getSystem(.Render).render_bounding_boxes = false;
    player = try Slime.spawnPlayer(.{.x = 400, .y = 400}, .slime1);
    ctx.player_id = player;

    const load_bar = try loading_bar.spawn(player);
    _ = try health_bar.spawn(player);
    _ = try energy_bar.spawn(player);

    const counter = try text_factory.spawn(.{.x = ctx.width_f32 / 2, .y = 50}, .black, "Hello World", 32);
    try prescient.update();
    const text_comp = try prescient.ent.getComponent(counter, .Text);

    var initing: bool = true;
    while(!raylib.windowShouldClose()) {
        try prescient.update();
        var buffer:[20]u8 = undefined;
        const content = try std.fmt.bufPrintZ(&buffer, "{d}", .{ctx.dead_slimes});
        text_comp.content = content;

        if(initing) {
            try spawnEnemy(max_enemies);
            ctx.sprites_loaded += 1;
            if(ctx.sprites_loaded >= 0) {
                try prescient.setSystemActive(.AIManager, true);
                prescient.ent.destroy(load_bar) catch continue;
        
                initing = false;
            }
        }
    }

}

pub fn spawnEnemy(ent_count: usize) !void {
    const Quadrant = enum {
        top,
        right,
        bottom,
        left,
    };
    for(0..ent_count) |_| {
        const quad: Quadrant = @enumFromInt(raylib.getRandomValue(0, 3));
        var x_val: i32 = undefined;
        var y_val: i32 = undefined;
       
        const wide_range = raylib.getRandomValue(-200,1000);

        //const invert: bool = if(raylib.getRandomValue(0,1) == 1) true else false;
        switch (quad) {
            .top => {
                x_val = wide_range;
                y_val = raylib.getRandomValue(-250, -50);            
            },
            .right => {
                x_val = raylib.getRandomValue(1050, 1250);            
                y_val = wide_range;
            },
            .bottom => {
                x_val = wide_range;
                y_val = raylib.getRandomValue(1050, 1250);            
            },
            .left => {
                x_val = raylib.getRandomValue(-250, -50);            
                y_val = wide_range;
            },
        }
        const x: f32 = @floatFromInt(x_val);
        const y: f32 = @floatFromInt(y_val);          

        _ = try Slime.spawnEnemy(.{.x = x, .y = y}, .slime2, player); 
    }
}
