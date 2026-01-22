const std = @import("std");
const Prescient = @import("../ecs/Prescient.zig").Prescient;
const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
const Query = @import("../ecs/Query.zig").QueryType;
const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;
const raylib = @import("raylib");
const comps = Prescient.Components.Types;
const comp_name = Prescient.Components.Names;

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
        has_controller: bool,
        state: ?Prescient.Components.Types.Slime.State,
        tag: comp_name,
        ent_ref: ?Prescient.Entity,
    };

    allocator: std.mem.Allocator,
    entities: std.ArrayList(CollisionEntity) = .{},
    active: bool = true,
    queries: struct {
        slimes: Query(.{.comps = &.{.Position, .Slime, .Sprite, .BoundingBox}}),
        waves: Query(.{.comps = &.{.Wave, .Position, .Sprite, .BoundingBox}}),
    },
    prescient: *Prescient = undefined,

    pub fn init(self: *Self) !void {
        self.prescient = try Prescient.getPrescient();
    }

    pub fn deinit(self: *Self) void {
        self.entities.deinit(self.allocator);
    }

    pub fn update(self: *Self) !void {
        // Collect all collidable entities for collision detection
        var entities = &self.entities;
        defer entities.clearRetainingCapacity();

        // Gather all collidable entities with their bounding boxes
        while (try self.queries.slimes.next()) |b| {
            for (b.entities, b.Position, b.Sprite, b.BoundingBox, b.Slime) |ent, pos, sprite, bbox, slime| {
                if (!bbox.active) continue;

                const has_controller = try self.prescient.ent.hasComponent(ent, .Controller);
                var col_ent = try getCollisionEntity(ent, pos, bbox, sprite, has_controller, null, .Slime);
                col_ent.state = slime.state; 

                try entities.append(self.allocator, col_ent);
            }
        }

        while (try self.queries.waves.next()) |b| {
            for (b.entities, b.Position, b.Sprite, b.BoundingBox) |ent, pos, sprite, bbox| {
                if (!bbox.active) continue;

                const slime_ref = try self.prescient.ent.getEntityComponentData(ent, .SlimeRef); 
                const col_ent = try getCollisionEntity(ent, pos, bbox, sprite, false, slime_ref.*, .Wave);

                try entities.append(self.allocator, col_ent);
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
                    if(entity_b.tag == .Wave and entity_a.tag == .Slime and entity_b.ent_ref.?.index != entity_a.id.index) {
                        std.debug.print("wave id: {} | slime id: {}", .{entity_b.ent_ref.?.index, entity_a.id.index});
                        //try self.prescient.ent.destroy(entity_a.id);
                    }
                    // Collision detected - handle collision response here
                    // std.debug.print("Collision between {} and {}\n", .{ entity_a.id, entity_b.id });
                    // std.debug.print("  A: x={d:.1}, y={d:.1}, w={d:.1}, h={d:.1}\n", .{ entity_a.x, entity_a.y, entity_a.width, entity_a.height });
                    // std.debug.print("  B: x={d:.1}, y={d:.1}, w={d:.1}, h={d:.1}\n", .{ entity_b.x, entity_b.y, entity_b.width, entity_b.height });
                }
            }
        }
    }

    fn getCollisionEntity(ent: Prescient.Entity, pos: *comps.Position, bbox: *comps.BoundingBox,  sprite: *comps.Sprite, has_controller: bool, ent_ref: ?Prescient.Entity, tag: comp_name) !CollisionEntity {

        const unscaled_width = if (bbox.width > 0) bbox.width else sprite.source.width;
        const unscaled_height = if (bbox.height > 0) bbox.height else sprite.source.height;

        const width = unscaled_width * sprite.scale;
        const height = unscaled_height * sprite.scale;

        // Position is where the sprite origin/pivot is placed
        // Calculate where the collision box center should be
        const collision_center_x = pos.x + (bbox.offset_x * sprite.scale);
        const collision_center_y = pos.y + (bbox.offset_y * sprite.scale);

        // Calculate top-left corner of collision box
        const bbox_x = collision_center_x - (width / 2.0);
        const bbox_y = collision_center_y - (height / 2.0);

        // WRITE computed bounding box data to component for other systems
        bbox.bbox_x = bbox_x;
        bbox.bbox_y = bbox_y;
        bbox.bbox_width = width;
        bbox.bbox_height = height;


        return  .{ 
            .id = ent,
            .x = bbox.bbox_x,
            .y = bbox.bbox_y,
            .width = bbox.bbox_width,
            .height = bbox.bbox_height,
            .active = bbox.active,
            .has_controller = has_controller,
            .state = null,
            .tag = tag,
            .ent_ref = ent_ref,
        };
    }
};
