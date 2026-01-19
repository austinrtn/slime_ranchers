const std = @import("std");
const System = @import("registries/SystemRegistry.zig").SystemName;
const Prescient = @import("ecs/Prescient.zig").Prescient;
const raylib = @import("raylib");
const Slime = @import("factories/player_slime.zig");
const StatusBar = @import("factories/StatusBar.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const prescient = try Prescient.init(allocator);
    defer prescient.deinit();

    //var general_pool = try prescient.getPool(.GeneralPool);
    
    const player_slime = Slime.PlayerSlime{};

    const player = try player_slime.spawn(.{.x = 400, .y = 400}, .slime1, true);
    _ = try player_slime.spawn(.{.x = 50, .y = 50}, .slime2, false); 

    const status_bar = try StatusBar.EnergyStatusBar.spawn(player);
    _ = status_bar;

    try prescient.update();
    
    while(!raylib.windowShouldClose()) {
        try prescient.update();
    }
}

