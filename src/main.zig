const std = @import("std");
const System = @import("registries/SystemRegistry.zig").SystemName;
const Prescient = @import("ecs/Prescient.zig").Prescient;
const raylib = @import("raylib");

var prescient: *Prescient = undefined;
const Slime = Prescient.Factories.Slime{};
var player: Prescient.Entity = undefined;

var enemy_count: usize = 0;
const max_enemies: usize = 100;
var ctx: *GlobalCtx = undefined;

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

    ctx = prescient.getGlobalCtx(); 

    var text_factory = try Prescient.Factories.TextFactory.init();
    try prescient.setSystemActive(.AIManager, false);

    prescient.getSystem(.Render).render_bounding_boxes = false;
    player = try Slime.spawnPlayer(.{.x = 400, .y = 400}, .slime1);
    ctx.player_id = player;

    const load_bar = try loading_bar.spawn(player);
    _ = try health_bar.spawn(player);
    _ = try energy_bar.spawn(player);

    const counter = try text_factory.spawn(.{.x = ctx.width_f32 / 2, .y = 50}, .black, "Hello World", 32);
    const text_comp = try prescient.ent.getComponent(counter, .Text);

    const state_text = try text_factory.spawn(.{.x = 700, .y = 700}, .black, "state", 16); 
    const state_text_comp: *Prescient.Components.Types.Text = try prescient.ent.getComponent(state_text, .Text);
    const slime: *Prescient.Components.Types.Slime = try prescient.ent.getComponent(player, .Slime);

    //***********************
    //GAME LOOP ***********
    //********************
    std.debug.print("\x1B[2J\x1B[H", .{});
    var initing: bool = true;
    try prescient.start();
    var state_counter: usize = 0;
    var last_state: Prescient.Components.Types.Slime.State = .idling;

    while(!raylib.windowShouldClose()) {
        try prescient.update();
        var buffer:[20]u8 = undefined;
        const content = try std.fmt.bufPrintZ(&buffer, "{d}", .{ctx.dead_slimes});
        text_comp.content = content;
        
        if(slime.state == last_state) {
//            state_counter += 1;
 //           std.debug.print("\r{s}: {d}", .{@tagName(slime.state), state_counter});
        } else {
            state_counter = 0;
            last_state = slime.state;
  //          std.debug.print("\n{s}{d}", .{@tagName(slime.state), state_counter});
        }
        state_text_comp.content = @tagName(slime.state);
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
        switch (quad) {
            .top => {
                x_val = wide_range;
                y_val = raylib.getRandomValue(-250, -50);            
            },
            .right => {
                x_val = raylib.getRandomValue(ctx.width + 50, ctx.width + 250);            
                y_val = wide_range;
            },
            .bottom => {
                x_val = wide_range;
                y_val = raylib.getRandomValue(ctx.height + 50, ctx.height + 250);            
            },
            .left => {
                x_val = raylib.getRandomValue(-250, -50);            
                y_val = wide_range;
            },
        }
        const x: f32 = @floatFromInt(x_val);
        const y: f32 = @floatFromInt(y_val);          
        const SlimeType = Prescient.Components.Types.Slime.SlimeType;

        const slime_type = if(raylib.getRandomValue(0,1) == 0)  SlimeType.slime2 else SlimeType.slime3;
        _ = try Slime.spawnEnemy(.{.x = x, .y = y}, slime_type, player); 
    }
}
