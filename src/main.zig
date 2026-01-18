const std = @import("std");
const System = @import("registries/SystemRegistry.zig").SystemName;
const Prescient = @import("ecs/Prescient.zig").Prescient;
const raylib = @import("raylib");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const prescient = try Prescient.init(allocator);
    defer prescient.deinit();

    const slime1 = try Prescient.compTypes.Slime.init(.slime2);

    var general_pool = try prescient.getPool(.GeneralPool);
    const player = try general_pool.createEntity(.{
        .Position = .{.x = 400, .y = 400},
        .Texture = slime1.current_texture,
        .Sprite = slime1.getSprite(),
        .Velocity = .{},
        .Slime = slime1,
        .Speed = 60.0,
        .Controller = .{},
        .Energy = .{.energy = 100, .max_energy = 100, .movement_cost = 10, .regen_per_frame = 15},
    });
     _= player;

    // Flush entity creation queue before loading textures
    try prescient.update();
    
    while(!raylib.windowShouldClose()) {
        try prescient.update();
    }
}

