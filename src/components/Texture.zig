const Prescient = @import("../ecs/Prescient.zig").Prescient;
const raylib = @import("raylib");

pub const Texture = raylib.Texture2D;

// pub const Texture = struct {
//     path: [:0]const u8, 
//     texture: raylib.Texture2D = undefined ,
//     loaded: bool = false, 
//
//     pub fn load(self: *@This()) !void {
//         const std = @import("std");
//         std.debug.print("Loading texture from: {s}\n", .{self.path});
//         self.texture = try raylib.loadTexture(self.path);
//         std.debug.print("Texture loaded: id={}, width={}, height={}\n", .{self.texture.id, self.texture.width, self.texture.height});
//         self.loaded = true;
//     }
//
//     pub fn unload(self: *@This()) void {
//         raylib.unloadTexture(self.texture);
//         self.loaded = false;
//     }
// };
