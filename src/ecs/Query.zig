const std = @import("std");
const ArrayList = std.ArrayList;
const CR = @import("../registries/ComponentRegistry.zig");
const PR = @import("../registries/PoolRegistry.zig");
const PM = @import("PoolManager.zig");
const MaskManager = @import("MaskManager.zig").GlobalMaskManager;
const EM = @import("EntityManager.zig");
const QT = @import("QueryTypes.zig");

pub fn QueryType(comptime config: QT.QueryConfig) type {
    const components = config.comps;
    const exclude = config.exclude;
    // PoolElementsType generates a heterogeneous struct where each field
    // has its own type with comptime POOL_NAME and STORAGE_STRATEGY
    const QResultType = QT.PoolElementsType(config);
    const POOL_COUNT = std.meta.fields(QResultType).len;

    return struct {
        const Self = @This();
        const pool_count = POOL_COUNT;
        pub const MASK = MaskManager.Comptime.createMask(components);
        pub const EXCLUDE_MASK = if (exclude) |exc| MaskManager.Comptime.createMask(exc) else 0;
        /// Struct type passed to forEach handlers: .entity: Entity, .ComponentName: *ComponentType
        pub const ComponentStruct = QT.ComponentPtrStruct(config);

        allocator: std.mem.Allocator,
        updated: bool = false,
        pool_manager: *PM.PoolManager,
        query_storage: QResultType = QT.findPoolElements(config),

        pool_index: usize = 0,
        archetype_index: usize = 0,

        // Track sparse batch allocations for cleanup
        sparse_batch_allocs: ArrayList(QT.ArchetypeCacheType(config)) = .{},

        pub fn init(allocator: std.mem.Allocator, pool_manager: *PM.PoolManager) !Self {
            var self = Self{
                .allocator = allocator,
                .pool_manager = pool_manager,
            };

            // Initialize the ArrayLists in each pool element
            inline for(std.meta.fields(QResultType)) |field| {
                var pool_element = &@field(self.query_storage, field.name);
                pool_element.archetype_indices = ArrayList(usize){};
                pool_element.archetype_cache = ArrayList(QT.ArchetypeCacheType(config)){};
                pool_element.sparse_cache = ArrayList(usize){};
            }

            // Cache all existing archetypes on init
            try self.cacheArchetypesFromPools(true);

            return self;
        }

        pub fn deinit(self: *Self) void {
            inline for(std.meta.fields(QResultType)) |field| {
                const pool_element = &@field(self.query_storage, field.name);

                // Free archetype cache pointer arrays
                for(pool_element.archetype_cache.items) |batch| {
                    inline for(components) |comp| {
                        self.allocator.free(@field(batch, @tagName(comp)));
                    }
                }
                pool_element.archetype_indices.deinit(self.allocator);
                pool_element.archetype_cache.deinit(self.allocator);
                pool_element.sparse_cache.deinit(self.allocator);
            }

            // Free sparse batch allocations (pointer arrays created during iteration)
            for(self.sparse_batch_allocs.items) |batch| {
                inline for(std.meta.fields(@TypeOf(batch))) |batch_field| {
                    self.allocator.free(@field(batch, batch_field.name));
                }
            }
            self.sparse_batch_allocs.deinit(self.allocator);
        }

        pub fn update(self: *Self) !void {
            // Free previous sparse batch allocations before starting new iteration cycle
            for(self.sparse_batch_allocs.items) |batch| {
                inline for(std.meta.fields(@TypeOf(batch))) |batch_field| {
                    self.allocator.free(@field(batch, batch_field.name));
                }
            }
            self.sparse_batch_allocs.clearRetainingCapacity();
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

                // Handle reallocated archetypes (update only, archetype pools only)
                if(!cache_all and PoolElemType.STORAGE_STRATEGY == .ARCHETYPE) {
                    for(pool.reallocated_archetypes.items) |arch| {
                        if(std.mem.indexOfScalar(usize, pool_element.archetype_indices.items, arch)) |idx| {
                            try self.cache(pool_element, pool, arch, idx);
                        }
                    }
                }
            }
        }

        fn cacheIfMatches(self: *Self, pool_element: anytype, pool: anytype, arch: usize) !void {
            const archetype_bitmask = pool.mask_list.items[arch];

            // Skip if archetype contains any excluded component
            if (EXCLUDE_MASK != 0 and (archetype_bitmask & Self.EXCLUDE_MASK) != 0) {
                return;
            }

            if(pool_element.access == .Direct) {
                try self.cache(pool_element, pool, arch, null);
            } else {
                if(MaskManager.maskContains(archetype_bitmask, Self.MASK)) {
                    try self.cache(pool_element, pool, arch, null);
                }
            }
        }

        pub fn cache(self: *Self, pool_element: anytype, pool: anytype, archetype_index: usize, index_in_pool_elem: ?usize) !void {
            if(@TypeOf(pool.*).storage_strategy == .ARCHETYPE) {
               return self.cacheArchetype(pool_element, pool, archetype_index, index_in_pool_elem);
            } else {
                try pool_element.sparse_cache.append(self.allocator, archetype_index);
            }
        }
        /// Convert archetype storage into Query Struct and append it to query cache
        /// Allocates pointer arrays for mutable access to storage
        fn cacheArchetype(self: *Self, pool_element: anytype, pool: anytype, archetype_index: usize, index_in_pool_elem: ?usize) !void {
            const ArchCacheType = comptime QT.ArchetypeCacheType(config);
            var archetype_cache: ArchCacheType = undefined;
            const storage = &pool.archetype_list.items[archetype_index];

            // Direct slice into entities storage
            archetype_cache.entities = storage.entities.items;

            // Allocate pointer arrays for mutable component access
            inline for(components) |comp| {
                const field_name = @tagName(comp);
                const ComponentType = CR.getTypeByName(comp);
                const items = @field(storage, field_name).?.items;
                const ptr_array = try self.allocator.alloc(*ComponentType, items.len);
                for(items, 0..) |*item, idx| {
                    ptr_array[idx] = item;
                }
                @field(archetype_cache, field_name) = ptr_array;
            }

            if(index_in_pool_elem) |indx|{
                // Re-caching existing archetype - free old allocations first
                const old_cache = pool_element.archetype_cache.items[indx];
                inline for(components) |comp| {
                    self.allocator.free(@field(old_cache, @tagName(comp)));
                }
                pool_element.archetype_cache.items[indx] = archetype_cache;
            }
            else{
                // New archetype - add to both lists
                try pool_element.archetype_indices.append(self.allocator, archetype_index);
                try pool_element.archetype_cache.append(self.allocator, archetype_cache);
            }
        }

        pub fn next(self: *Self) !?QT.ArchetypeCacheType(config){
            // Only require update() before first iteration (at start position)
            if(self.pool_index == 0 and self.archetype_index == 0 and !self.updated) {
                return error.QueryNotUpdated;
            }

            while(true){
                // Check if we've exhausted all pools
                if(self.pool_index >= POOL_COUNT) {
                    self.pool_index = 0;
                    self.archetype_index = 0;
                    return null;
                }

                switch(self.pool_index){
                    inline 0...(pool_count - 1) =>|i|{
                        const field = std.meta.fields(QResultType)[i];
                        const pool_elem = &@field(self.query_storage, field.name);
                        const PoolElemType = @TypeOf(pool_elem.*);

                        if(PoolElemType.STORAGE_STRATEGY == .ARCHETYPE) {
                            if(pool_elem.archetype_cache.items.len > 0) {
                                const batch = pool_elem.archetype_cache.items[self.archetype_index];
                                self.archetype_index += 1;

                                if(self.archetype_index >= pool_elem.archetype_cache.items.len){
                                    self.archetype_index = 0;
                                    self.pool_index += 1;
                                }

                                return batch;
                            }
                            else {
                                self.pool_index += 1;
                                if(self.pool_index >= POOL_COUNT) {
                                    self.archetype_index = 0;
                                    self.pool_index = 0;
                                    return null;
                                }
                            }
                        }
                        else if(PoolElemType.STORAGE_STRATEGY == .SPARSE){
                            if(self.archetype_index < pool_elem.sparse_cache.items.len) {
                                // POOL_NAME is comptime - no inline switch needed!
                                const pool = self.pool_manager.getOrCreatePool(PoolElemType.POOL_NAME) catch unreachable;

                                const v_arch_index = pool_elem.sparse_cache.items[self.archetype_index];
                                const storage_indexes = pool.virtual_archetypes.items[v_arch_index];

                                var batch: QT.ArchetypeCacheType(config) = undefined;

                                // Build entities slice
                                const entities_array = self.allocator.alloc(EM.Entity, storage_indexes.items.len) catch unreachable;
                                for (storage_indexes.items, 0..) |ent_index, idx| {
                                    entities_array[idx] = pool.storage.entities.items[ent_index].?;
                                }
                                batch.entities = entities_array;

                                inline for(components) |component| {
                                    const ComponentType = CR.getTypeByName(component);
                                    // Allocate pointer array for mutable access to sparse storage
                                    const ptr_array = self.allocator.alloc(*ComponentType, storage_indexes.items.len) catch unreachable;

                                    for (storage_indexes.items, 0..) |ent_index, idx| {
                                        ptr_array[idx] = &(@field(pool.storage, @tagName(component)).items[ent_index].?);
                                    }
                                    @field(batch, @tagName(component)) = ptr_array;
                                }

                                self.archetype_index += 1;

                                if(self.archetype_index >= pool_elem.sparse_cache.items.len){
                                    self.archetype_index = 0;
                                    self.pool_index += 1;
                                }

                                // Track allocation for cleanup
                                self.sparse_batch_allocs.append(self.allocator, batch) catch unreachable;
                                return batch;
                            }
                            else {
                                self.pool_index += 1;
                                if(self.pool_index >= POOL_COUNT) {
                                    self.archetype_index = 0;
                                    self.pool_index = 0;

                                    return null;
                                }
                            }
                        }
                    },
                    else => unreachable,
                }
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

                    inline for (components) |comp| {
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

                    inline for (components) |comp| {
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
