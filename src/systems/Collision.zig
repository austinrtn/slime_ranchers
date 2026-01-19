const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;
const raylib = @import("raylib");

pub const Collision = struct {
    const Self = @This();

    // Dependency declarations for compile-time system ordering
    pub const reads = [_]type{};
    pub const writes = [_]type{};

    const CollisionEntity = struct {
        id: Prescient.Entity,
        x: f32,
        y: f32,
        width: f32,
        height: f32,
        active: bool,
    };

    allocator: std.mem.Allocator,
    active: bool = true,
    queries: struct {
        slimes: Query(.{.comps = &.{.Position, .Slime, .Sprite, .Collidable}})
    },

    pub fn update(self: *Self) !void {
        // Collect all collidable entities for collision detection
        var entities = std.ArrayList(CollisionEntity){};
        defer entities.deinit(self.allocator);

        // Gather all collidable entities with their bounding boxes
        while (try self.queries.slimes.next()) |b| {
            for (b.entities, b.Position, b.Sprite, b.Collidable) |entity_id, pos, sprite, collidable| {
                if (!collidable.active) continue;

                // Calculate bounding box dimensions
                // Use custom collidable dimensions if set, otherwise use full sprite frame
                const unscaled_width = if (collidable.width > 0) collidable.width else sprite.source.width;
                const unscaled_height = if (collidable.height > 0) collidable.height else sprite.source.height;

                const width = unscaled_width * sprite.scale;
                const height = unscaled_height * sprite.scale;

                // Position is where the sprite origin/pivot is placed
                // Calculate where the collision box center should be
                const collision_center_x = pos.x + (collidable.offset_x * sprite.scale);
                const collision_center_y = pos.y + (collidable.offset_y * sprite.scale);

                // Calculate top-left corner of collision box
                const bbox_x = collision_center_x - (width / 2.0);
                const bbox_y = collision_center_y - (height / 2.0);

                // Draw debug collision box
                raylib.drawRectangleLinesEx(
                    .{ .x = bbox_x, .y = bbox_y, .width = width, .height = height },
                    2.0,
                    .red
                );

                try entities.append(self.allocator, .{
                    .id = entity_id,
                    .x = bbox_x,
                    .y = bbox_y,
                    .width = width,
                    .height = height,
                    .active = collidable.active,
                });
            }
        }

        // Check for collisions between all pairs of entities
        for (entities.items, 0..) |entity_a, i| {
            for (entities.items[i + 1 ..]) |entity_b| {
                // AABB collision detection
                const colliding = entity_a.x < entity_b.x + entity_b.width and
                    entity_a.x + entity_a.width > entity_b.x and
                    entity_a.y < entity_b.y + entity_b.height and
                    entity_a.y + entity_a.height > entity_b.y;

                if (colliding) {
                    // Collision detected - handle collision response here
                    std.debug.print("Collision between {} and {}\n", .{ entity_a.id, entity_b.id });
                    std.debug.print("  A: x={d:.1}, y={d:.1}, w={d:.1}, h={d:.1}\n", .{ entity_a.x, entity_a.y, entity_a.width, entity_a.height });
                    std.debug.print("  B: x={d:.1}, y={d:.1}, w={d:.1}, h={d:.1}\n", .{ entity_b.x, entity_b.y, entity_b.width, entity_b.height });
                    // TODO: Add collision response logic (e.g., push apart, damage, events, etc.)
                }
            }
        }
    }
};
