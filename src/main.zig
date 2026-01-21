const std = @import("std");
const System = @import("registries/SystemRegistry.zig").SystemName;
const Prescient = @import("ecs/Prescient.zig").Prescient;
const raylib = @import("raylib");

pub fn main() !void {
    var health_bar = Prescient.Factories.StatusBar.HealthStatusBar;
    var energy_bar = Prescient.Factories.StatusBar.EnergyStatusBar;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const prescient = try Prescient.init(allocator);
    defer prescient.deinit();
    
    const Slime = Prescient.Factories.Slime{};
    var Wave = try Prescient.Factories.WaveFactory.init();

    prescient.getSystem(.Render).render_bounding_boxes = true;
    const player = try Slime.spawnPlayer(.{.x = 400, .y = 400}, .slime1);
    _ = try Slime.spawnEnemy(.{.x = 50, .y = 50}, .slime2); 
    const wave = try Wave.spawn(.{.position = .{.x = 100, .y = 100,}, .slime_ref = player});

    _ = wave;

    _ = try health_bar.spawn(player);
    _ = try energy_bar.spawn(player);

    try prescient.update();
    
    while(!raylib.windowShouldClose()) {
        try prescient.update();
        // const slime = try prescient.ent.getEntityComponentData(player, .Slime);
        // std.debug.print("\nState: {s} | Last: {s}", .{@tagName(slime.state), @tagName(slime.last_state)});
    }
}

