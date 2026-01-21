const std = @import("std");
const System = @import("registries/SystemRegistry.zig").SystemName;
const Prescient = @import("ecs/Prescient.zig").Prescient;
const raylib = @import("raylib");

pub fn main() !void {
    const Slime = Prescient.Factories.Slime{};
    var health_bar = Prescient.Factories.StatusBar.HealthStatusBar;
    var energy_bar = Prescient.Factories.StatusBar.EnergyStatusBar;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const prescient = try Prescient.init(allocator);
    defer prescient.deinit();

    prescient.getSystem(.Render).render_bounding_boxes = false;

    const player = try Slime.spawnPlayer(.{.x = 400, .y = 400}, .slime1);
    _ = try Slime.spawnEnemy(.{.x = 50, .y = 50}, .slime2); 

    _ = try health_bar.spawn(player);
    _ = try energy_bar.spawn(player);

    try prescient.update();
    
    while(!raylib.windowShouldClose()) {
        try prescient.update();
    }
}

