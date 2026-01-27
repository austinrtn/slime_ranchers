const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;
const raylib = @import("raylib");

pub const Render = struct {
    const Self = @This();
    pub const enabled: bool = true;

    allocator: std.mem.Allocator,
    active: bool = true,
    width: i32 = 800,
    height: i32 = 800,
    frame: u32 = 0,
    frame_counter: u32 = 0,
    frames_per_animation: u32 = 60,  // Update animation every 10 frames (~6 FPS)
    render_bounding_boxes: bool = false,

    queries: struct {
        text: Query(.{.read = &.{.Position, .Text, .Color}, .write = &.{}}),
        textures: Query(.{.read = &.{.Position, .Texture}, .write = &.{}}),
        sprites: Query(.{.read = &.{.Position, .Texture, .Sprite}, .write = &.{}}),
        rectangles: Query(.{.read = &.{.Position, .Rectangle, .Color}, .write = &.{}}),
        circles: Query(.{.read = &.{.Position, .Circle, .Color}, .write = &.{}}),
        status_bars: Query(.{.read = &.{.Position, .StatusBar, .Color}, .write = &.{}}),
        bounding_boxes: Query(.{.read = &.{.BoundingBox}, .write = &.{}}),
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
        try self.drawText();
        if (self.render_bounding_boxes) {
            try self.drawBoundingBoxes();
        }
    }

    fn drawText(self: *Self) !void {
        try self.queries.text.forEach(self, struct{
            pub fn run(_: anytype, c:anytype) !bool {
                const text = c.Text;
                const pos = c.Position;
                const text_width = raylib.measureText(text.content, text.font_size);
                const x_converted: i32 = @intFromFloat(pos.x);
                const x: i32 = x_converted -  @divTrunc(text_width, 2);
                const y: i32 = @intFromFloat(pos.y);

                raylib.drawText(text.content, x, y,  text.font_size, c.Color.*);
                return true;
            }
        }); 
    }

    fn drawSprites(self: *Self) !void {
        try self.queries.sprites.forEach(self, struct{
            pub fn run(data: anytype, c: anytype) !bool {
                _ = data;
                const pos = c.Position;
                const sprite = c.Sprite;
                const texture = c.Texture;

                if(!sprite.is_visible) return true;

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
                return true;
            }
        });
    }
    
    fn drawStatusBars(self: *Self) !void {
        try self.queries.status_bars.forEach(null, struct {
            pub fn run(_: anytype, c: anytype) !bool {
                const pos = c.Position;
                const status_bar = c.StatusBar;
                const color = c.Color;
                const current_bar = status_bar.current_size;
                const max_bar = status_bar.max_size;

                const current_size_vect = raylib.Vector2{.x = current_bar.width, .y = current_bar.height};
                const max_size_vect = raylib.Vector2{.x = max_bar.width, .y = max_bar.height};

                raylib.drawRectangleV(pos.getVector(), max_size_vect, raylib.Color{.r = 128, .b = 128, .g = 128, .a = 155});
                raylib.drawRectangleV(pos.getVector(), current_size_vect, color.*);
                return true;
            }
        });
    }

    fn drawCircles(self: *Self) !void {
        try self.queries.circles.forEach(self, struct{
            pub fn run(_:anytype, c: anytype) !bool{
                raylib.drawCircleV(c.Position.getVector(), c.Circle.radius, c.Color.*);
                return true;
            }
        });
    }

    fn drawRectangles(self: *Self) !void {
        try self.queries.rectangles.forEach(self, struct {
            pub fn run(_:anytype, c: anytype) !bool {
                raylib.drawRectangleV(c.Position.getVector(), c.Rectangle.getVector(), c.Color.*);
                return true;
            }
        });
    }

    fn drawBoundingBoxes(self: *Self) !void {
        try self.queries.bounding_boxes.forEach(null, struct{
            pub fn run(_: anytype, c: anytype) !bool {
                const bbox = c.BoundingBox;
                if (!bbox.active) return true;

                raylib.drawRectangleLinesEx(
                    .{
                        .x = bbox.bbox_x,
                        .y = bbox.bbox_y,
                        .width = bbox.bbox_width,
                        .height = bbox.bbox_height
                    },
                    2.0,
                    .red
                );
                return true;
            }
        });
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        raylib.closeWindow();
    }
};
