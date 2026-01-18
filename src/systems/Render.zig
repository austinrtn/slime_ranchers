const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;
const raylib = @import("raylib");

pub const Render = struct {
    const Self = @This();

    // Dependency declarations for compile-time system ordering
    pub const reads = [_]type{};
    pub const writes = [_]type{};

    allocator: std.mem.Allocator,
    active: bool = true,
    width: i32 = 800,
    height: i32 = 800,
    frame: u32 = 0,
    frame_counter: u32 = 0,
    frames_per_animation: u32 = 60,  // Update animation every 10 frames (~6 FPS)

    queries: struct {
        textures: Query(&.{.Position, .Texture}),
        sprites: Query(&.{.Position, .Texture, .Sprite}),
        circles: Query(&.{.Position, .Circle}),
    },

    pub fn init(self: *Self) !void {
        raylib.initWindow(self.width, self.height, "title");
    }

    pub fn loadTextures(self: *Self) !void {
        try self.queries.textures.update();

        var count: usize = 0;
        while(try self.queries.textures.next()) |b| {
            count += 1;
            for(b.Texture) |text| {
                try text.load();
            }
        }
    }

    pub fn update(self: *Self) !void {
        raylib.beginDrawing();
        defer raylib.endDrawing();

        raylib.clearBackground(.ray_white);

        try self.queries.sprites.update();
        while(try self.queries.sprites.next()) |b| {
            for(b.Position, b.Texture, b.Sprite) |pos, texture, sprite| {

                // Destination rectangle (where to draw on screen)
                // Position is where the origin/pivot point will be
                const dest = raylib.Rectangle{
                    .x = pos.x,
                    .y = pos.y,
                    .width = sprite.source.width * sprite.scale,
                    .height = sprite.source.height * sprite.scale,
                };

                // Scale the origin for the scaled sprite
                const scaled_origin = raylib.Vector2{
                    .x = sprite.origin.x * sprite.scale,
                    .y = sprite.origin.y * sprite.scale,
                };

                raylib.drawTexturePro(
                    texture.*,
                    sprite.source,
                    dest,
                    scaled_origin,  // Use scaled origin for proper pivot
                    sprite.rotation,
                    sprite.tint,
                );

                sprite.nextFrame();
            }
        }

        try self.queries.circles.update();
        while(try self.queries.circles.next()) |b| {
            for(b.Position, b.Circle) |pos, circle| {
                raylib.drawCircleV(pos.getVector(), circle.radius, circle.color);
            }
        }
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        raylib.closeWindow();
    }
};
