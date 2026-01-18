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
        rectangles: Query(&.{.Position, .Rectangle, .Color}),
        circles: Query(&.{.Position, .Circle, .Color}),
        status_bars: Query(&.{.Position, .StatusBar, .Color}),
    },

    pub fn init(self: *Self) !void {
        raylib.initWindow(self.width, self.height, "title");
    }

    pub fn update(self: *Self) !void {
        raylib.beginDrawing();
        defer raylib.endDrawing();

        raylib.clearBackground(.ray_white);
        try self.drawSprites();
        try self.drawStatusBars();
        try self.drawRectangles(); 
        try self.drawCircles();
    }

    fn drawSprites(self: *Self) !void {
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
            }
        }

    }
    
    fn drawStatusBars(self: *Self) !void {
        while(try self.queries.status_bars.next()) |b| {
            for(b.Position, b.StatusBar, b.Color) |pos, statusBar, color| {
                const current_bar = statusBar.current_size;
                const max_bar = statusBar.max_size;
                const current_size_vect = raylib.Vector2{.x = current_bar.width, .y = current_bar.height};
                const max_size_vect = raylib.Vector2{.x = max_bar.width, .y = max_bar.height};

                raylib.drawRectangleV(pos.getVector(), max_size_vect, raylib.Color{.r = 128, .b = 128, .g = 128, .a = 155});
                raylib.drawRectangleV(pos.getVector(), current_size_vect, color.*);
            }
        }
    }

    fn drawCircles(self: *Self) !void {
        while(try self.queries.circles.next()) |b| {
            for(b.Position, b.Circle, b.Color) |pos, circle, color| {
                raylib.drawCircleV(pos.getVector(), circle.radius, color.*);
            }
        }
    }

    fn drawRectangles(self: *Self) !void {
        while(try self.queries.rectangles.next()) |b| {
            for(b.Position, b.Rectangle, b.Color) |pos, rect, color| {
                raylib.drawRectangleV(pos.getVector(), rect.getVector(), color.*);
            }
        }
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        raylib.closeWindow();
    }
};
