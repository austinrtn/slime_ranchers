const Prescient = @import("../ecs/Prescient.zig").Prescient;
const raylib = @import("raylib");
const std = @import("std");

pub const Sprite = struct {
    pub const AnimationMode = enum {
        looping,  // Animation loops continuously (idle, walk, etc.)
        once,     // Animation plays once then stops (attack, death, etc.)
    };
    // Source rectangle from sprite sheet (which frame to draw)
    source: raylib.Rectangle,

    // Visual properties
    scale: f32 = 1.0,
    rotation: f32 = 0.0,  // Rotation in radians
    tint: raylib.Color = .white,
    origin: raylib.Vector2 = .{.x = 0, .y = 0},  // Pivot point for rotation/scaling

    // Sprite sheet layout
    frame_width: f32 = 0.0,
    frame_height: f32 = 0.0,
    grid_columns: u32 = 1,  // Number of frames per row in sprite sheet

    // Animation state
    frame_index: u32 = 0,       // Current animation frame (0 to animation_length-1)
    animation_length: u32 = 1,  // Total frames in this animation
    animation_delay: f32 = 0.1, // Seconds to wait before advancing animation
    delay_counter: f32 = 0.0,   // Internal counter for animation timing (accumulated time)
    animation_mode: AnimationMode = .looping,  // Whether animation loops or plays once
    animation_complete: bool = false,           // Set to true when a .once animation finishes
                                                //
    is_visible: bool = true,

    pub fn nextFrame(self: *@This()) void {
        // Skip if animation is complete (for .once mode)
        if (self.animation_mode == .once and self.animation_complete) {
            return;
        }

        // Accumulate delta time
        self.delay_counter += raylib.getFrameTime();
        if(self.delay_counter < self.animation_delay) {
            return;
        }

        // Subtract delay to preserve overflow time for smooth animation
        self.delay_counter -= self.animation_delay;

        // Advance to next animation frame
        self.frame_index += 1;
        if(self.frame_index >= self.animation_length) {
            if (self.animation_mode == .once) {
                // For .once animations, stay on the last frame and mark as complete
                self.frame_index = self.animation_length - 1;
                self.animation_complete = true;
            } else {
                // For .looping animations, wrap to beginning
                self.frame_index = 0;
            }
        }

        // Calculate position in sprite sheet grid
        const row = self.frame_index / self.grid_columns;
        const col = self.frame_index % self.grid_columns;

        // Update source rectangle to point to the current frame
        self.source.x = @as(f32, @floatFromInt(col)) * self.frame_width;
        self.source.y = @as(f32, @floatFromInt(row)) * self.frame_height;
        self.source.width = self.frame_width;
        self.source.height = self.frame_height;
    }

    pub fn initFromSpriteSheet(
        frame_width: f32,
        frame_height: f32,
        grid_columns: u32,
        animation_length: u32,
        animation_delay: f32,
        scale: f32,
    ) @This() {
        return .{
            .source = .{
                .x = 0,
                .y = 0,
                .width = frame_width,
                .height = frame_height,
            },
            .frame_width = frame_width,
            .frame_height = frame_height,
            .grid_columns = grid_columns,
            .animation_length = animation_length,
            .animation_delay = animation_delay,
            .scale = scale,
            // Set origin to center for proper rotation
            .origin = .{
                .x = frame_width / 2.0,
                .y = frame_height / 2.0,
            },
        };
    }
};
