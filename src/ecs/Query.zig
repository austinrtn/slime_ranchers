const std = @import("std");
const ArrayList = std.ArrayList;
const PM = @import("PoolManager.zig");
const MaskManager = @import("MaskManager.zig").GlobalMaskManager;
const QT = @import("QueryTypes.zig");

pub fn QueryType(comptime config: QT.QueryConfig) type {
    const read_components = config.read;
    const write_components = config.write;
    const all_components = config.allComponents();
    const exclude = config.exclude;
    // PoolElementsType generates a heterogeneous struct where each field
    // has its own type with comptime POOL_NAME and STORAGE_STRATEGY
    const QResultType = QT.PoolElementsType(config);

    return struct {
        const Self = @This();

        /// Component dependency lists for system ordering
        pub const READ_COMPONENTS = read_components;
        pub const WRITE_COMPONENTS = write_components;
        pub const ALL_COMPONENTS = all_components;

        pub const MASK = MaskManager.Comptime.createMask(all_components);
        pub const EXCLUDE_MASK = if (exclude) |exc| MaskManager.Comptime.createMask(exc) else 0;
        /// Struct type passed to forEach handlers: .entity: Entity, .ComponentName: *const T (read) or *T (write)
        pub const ComponentStruct = QT.ComponentPtrStruct(config);

        allocator: std.mem.Allocator,
        updated: bool = false,
        pool_manager: *PM.PoolManager,
        query_storage: QResultType = QT.findPoolElements(config),

        pub fn init(allocator: std.mem.Allocator, pool_manager: *PM.PoolManager) !Self {
            var self = Self{
                .allocator = allocator,
                .pool_manager = pool_manager,
            };

            // Initialize the ArrayLists in each pool element
            inline for(std.meta.fields(QResultType)) |field| {
                var pool_element = &@field(self.query_storage, field.name);
                pool_element.archetype_indices = ArrayList(usize){};
                pool_element.sparse_cache = ArrayList(usize){};
            }

            // Cache all existing archetypes on init
            try self.cacheArchetypesFromPools(true);

            return self;
        }

        pub fn deinit(self: *Self) void {
            inline for(std.meta.fields(QResultType)) |field| {
                const pool_element = &@field(self.query_storage, field.name);
                pool_element.archetype_indices.deinit(self.allocator);
                pool_element.sparse_cache.deinit(self.allocator);
            }
        }

        pub fn update(self: *Self) !void {
            try self.cacheArchetypesFromPools(false);
            self.updated = true;
        }

        fn cacheArchetypesFromPools(self: *Self, cache_all: bool) !void {
            inline for(std.meta.fields(QResultType)) |field| {
                const pool_element = &@field(self.query_storage, field.name);
                const PoolElemType = @TypeOf(pool_element.*);
                const pool = try self.pool_manager.getOrCreatePool(PoolElemType.POOL_NAME);

                // Get total archetype count based on storage strategy
                const total_count = if(PoolElemType.STORAGE_STRATEGY == .ARCHETYPE)
                    pool.archetype_list.items.len
                else
                    pool.virtual_archetypes.items.len;

                const arch_count = if(cache_all) total_count else pool.new_archetypes.items.len;

                for(0..arch_count) |i| {
                    const arch = if(cache_all) i else pool.new_archetypes.items[i];
                    try self.cacheIfMatches(pool_element, pool, arch);
                }
            }
        }

        fn cacheIfMatches(self: *Self, pool_element: anytype, pool: anytype, arch: usize) !void {
            const archetype_bitmask = pool.mask_list.items[arch];

            // Skip if archetype contains any excluded component
            if (EXCLUDE_MASK != 0 and (archetype_bitmask & Self.EXCLUDE_MASK) != 0) {
                return;
            }

            if (pool_element.access == .Direct) {
                try self.cacheArchetypeIndex(pool_element, pool, arch);
            } else {
                if (MaskManager.maskContains(archetype_bitmask, Self.MASK)) {
                    try self.cacheArchetypeIndex(pool_element, pool, arch);
                }
            }
        }

        /// Track archetype index for iteration. forEach accesses storage directly.
        fn cacheArchetypeIndex(self: *Self, pool_element: anytype, pool: anytype, archetype_index: usize) !void {
            _ = pool;
            if (@TypeOf(pool_element.*).STORAGE_STRATEGY == .ARCHETYPE) {
                try pool_element.archetype_indices.append(self.allocator, archetype_index);
            } else {
                try pool_element.sparse_cache.append(self.allocator, archetype_index);
            }
        }

        /// Iterates over all matching entities, calling handler.run() for each.
        /// For archetype pools: zero allocation, accesses contiguous storage directly.
        ///
        /// ctx: Any type for external state (delta_time, system ref, etc). Pass {} if not needed.
        /// handler: Struct with `pub fn run(ctx: @TypeOf(ctx), comps: ComponentStruct) !bool`
        ///          Return true to continue iteration, false to stop.
        pub fn forEach(self: *Self, ctx: anytype, comptime handler: type) !void {
            if (!@hasDecl(handler, "run")) {
                @compileError("forEach handler must have a 'run' declaration");
            }

            inline for (std.meta.fields(QResultType)) |field| {
                const pool_elem = &@field(self.query_storage, field.name);
                const PoolElemType = @TypeOf(pool_elem.*);

                if (PoolElemType.STORAGE_STRATEGY == .ARCHETYPE) {
                    if (!try self.forEachArchetype(ctx, handler, pool_elem)) return;
                } else {
                    if (!try self.forEachSparse(ctx, handler, pool_elem)) return;
                }
            }
        }

        fn forEachArchetype(self: *Self, ctx: anytype, comptime handler: type, pool_elem: anytype) !bool {
            const PoolElemType = @TypeOf(pool_elem.*);
            const pool = self.pool_manager.getOrCreatePool(PoolElemType.POOL_NAME) catch unreachable;

            for (pool_elem.archetype_indices.items) |arch_idx| {
                const storage = &pool.archetype_list.items[arch_idx];
                const entity_count = storage.entities.items.len;

                for (0..entity_count) |i| {
                    var comp_struct: ComponentStruct = undefined;
                    comp_struct.entity = storage.entities.items[i];

                    // Read components get *const T pointers
                    inline for (read_components) |comp| {
                        const field_name = @tagName(comp);
                        const items = @field(storage, field_name).?.items;
                        @field(comp_struct, field_name) = &items[i];
                    }

                    // Write components get *T pointers
                    inline for (write_components) |comp| {
                        const field_name = @tagName(comp);
                        const items = @field(storage, field_name).?.items;
                        @field(comp_struct, field_name) = &items[i];
                    }

                    if (!try handler.run(ctx, comp_struct)) return false;
                }
            }
            return true;
        }

        fn forEachSparse(self: *Self, ctx: anytype, comptime handler: type, pool_elem: anytype) !bool {
            const PoolElemType = @TypeOf(pool_elem.*);
            const pool = self.pool_manager.getOrCreatePool(PoolElemType.POOL_NAME) catch unreachable;

            for (pool_elem.sparse_cache.items) |v_arch_index| {
                const storage_indexes = pool.virtual_archetypes.items[v_arch_index];

                for (storage_indexes.items) |ent_index| {
                    var comp_struct: ComponentStruct = undefined;
                    comp_struct.entity = pool.storage.entities.items[ent_index].?;

                    // Read components get *const T pointers
                    inline for (read_components) |comp| {
                        const field_name = @tagName(comp);
                        @field(comp_struct, field_name) = &(@field(pool.storage, field_name).items[ent_index].?);
                    }

                    // Write components get *T pointers
                    inline for (write_components) |comp| {
                        const field_name = @tagName(comp);
                        @field(comp_struct, field_name) = &(@field(pool.storage, field_name).items[ent_index].?);
                    }

                    if (!try handler.run(ctx, comp_struct)) return false;
                }
            }
            return true;
        }
    };
}
