const std = @import("std");
const ArrayList = std.ArrayList;
const CR = @import("../registries/ComponentRegistry.zig");
const PR = @import("../registries/PoolRegistry.zig");
const StorageStrategy = @import("StorageStrategy.zig").StorageStrategy;
const MaskManager = @import("MaskManager.zig").GlobalMaskManager;
const StructField = std.builtin.Type.StructField;
const Entity = @import("EntityManager.zig").Entity;

/// Configuration for query filtering
pub const QueryConfig = struct {
    read: []const CR.ComponentName = &.{},
    write: []const CR.ComponentName = &.{},
    exclude: ?[]const CR.ComponentName = null,
    pools: ?[]const PR.PoolName = null,

    /// Returns all components (read ++ write) for mask creation and pool matching
    pub fn allComponents(comptime self: QueryConfig) []const CR.ComponentName {
        return self.read ++ self.write;
    }
};

/// Validates that read and write sets are disjoint at comptime
pub fn validateQueryConfig(comptime config: QueryConfig) void {
    for (config.read) |read_comp| {
        for (config.write) |write_comp| {
            if (read_comp == write_comp) {
                @compileError("Component '" ++ @tagName(read_comp) ++ "' cannot be in both read and write sets. Use write only (it implies read access).");
            }
        }
    }
}

// Determines how a pool's archetypes are accessed during query iteration
pub const ArchetypeAccess = enum{
    // All archetypes in the pool are guaranteed to match the query (all query components are required)
    Direct,
    // Archetypes must be individually checked since some query components are optional
    Lookup,
};

/// Generates struct type for forEach callbacks with single component pointers.
/// Fields: .entity: Entity, .ComponentName: *const T (read) or *T (write)
pub fn ComponentPtrStruct(comptime config: QueryConfig) type {
    comptime validateQueryConfig(config);

    const read_comps = config.read;
    const write_comps = config.write;
    const total_comps = read_comps.len + write_comps.len;
    var fields: [total_comps + 1]StructField = undefined;

    // entity field (single entity, not slice)
    fields[0] = StructField{
        .name = "entity",
        .type = Entity,
        .alignment = @alignOf(Entity),
        .default_value_ptr = null,
        .is_comptime = false,
    };

    // Read component pointer fields (*const T - immutable)
    for (read_comps, 1..) |comp, i| {
        const name = @tagName(comp);
        const T = *const CR.getTypeByName(comp);
        fields[i] = StructField{
            .name = name,
            .type = T,
            .alignment = @alignOf(T),
            .default_value_ptr = null,
            .is_comptime = false,
        };
    }

    // Write component pointer fields (*T - mutable)
    for (write_comps, read_comps.len + 1..) |comp, i| {
        const name = @tagName(comp);
        const T = *CR.getTypeByName(comp);
        fields[i] = StructField{
            .name = name,
            .type = T,
            .alignment = @alignOf(T),
            .default_value_ptr = null,
            .is_comptime = false,
        };
    }

    return @Type(.{
        .@"struct" = .{
            .fields = &fields,
            .layout = .auto,
            .is_tuple = false,
            .backing_integer = null,
            .decls = &.{},
        },
    });
}

/// PoolElementType - One type PER pool with comptime constants
/// This allows Query to access pool info at comptime without inline switch
pub fn PoolElementType(comptime pool_name: PR.PoolName, comptime config: QueryConfig) type {
    _ = config; // Used for type consistency across query system
    return struct {
        pub const POOL_NAME = pool_name;
        pub const STORAGE_STRATEGY = PR.getPoolFromName(pool_name).storage_strategy;

        access: ArchetypeAccess,
        archetype_indices: ArrayList(usize),
        sparse_cache: ArrayList(usize),
    };
}

/// Check if a pool should be included based on the pools filter
fn shouldIncludePool(comptime config: QueryConfig, comptime pool_index: usize) bool {
    if (config.pools) |pool_filter| {
        const pool_name: PR.PoolName = @enumFromInt(pool_index);
        for (pool_filter) |allowed_pool| {
            if (pool_name == allowed_pool) {
                return true;
            }
        }
        return false;
    }
    // No filter means include all pools
    return true;
}

pub fn countMatchingPools(comptime config: QueryConfig) comptime_int {
    const components = config.allComponents();
    const exclude = config.exclude;
    var count: comptime_int = 0;

    for(PR.pool_types, 0..) |pool_type, i| {
        // Pool filter check (FIRST)
        if (!shouldIncludePool(config, i)) {
            continue;
        }

        var query_match = true;
        var req_match = true;
        var excluded = false;

        // Check exclusion first - if excluded component is in REQ_MASK, skip entire pool
        if(exclude) |exc| {
            for(exc) |exc_comp| {
                const exc_bit = MaskManager.Comptime.componentToBit(exc_comp);
                if(MaskManager.maskContains(pool_type.REQ_MASK, exc_bit)) {
                    excluded = true;
                    break;
                }
                // If excluded component is in pool_mask but not REQ_MASK,
                // pool still matches but needs Lookup access
                if(MaskManager.maskContains(pool_type.pool_mask, exc_bit)) {
                    req_match = false;
                }
            }
        }

        if(excluded) {
            continue;
        }

        for(components) |component| {
            const component_bit = MaskManager.Comptime.componentToBit(component);
            const in_pool = MaskManager.maskContains(pool_type.pool_mask, component_bit);

            if(!in_pool) {
                query_match = false;
                req_match = false;
                break;
            }

            if(req_match) {
                const contained_in_req = MaskManager.maskContains(pool_type.REQ_MASK, component_bit);
                if(!contained_in_req) {
                    req_match = false;
                }
            }
        }

        if(req_match or query_match) {
            count += 1;
        }
    }
    return count;
}

/// Match result struct for pool lookup
const PoolMatch = struct {
    pool_name: PR.PoolName,
    access: ArchetypeAccess,
};

/// Returns array of matching pool names with their access types
fn findMatchingPools(comptime config: QueryConfig) [countMatchingPools(config)]PoolMatch {
    const components = config.allComponents();
    const exclude = config.exclude;
    const count = countMatchingPools(config);
    var matches: [count]PoolMatch = undefined;
    var idx: usize = 0;

    for(PR.pool_types, 0..) |pool_type, i| {
        // Pool filter check (FIRST)
        if (!shouldIncludePool(config, i)) {
            continue;
        }

        var query_match = true;
        var req_match = true;
        var excluded = false;

        // Check exclusion first - if excluded component is in REQ_MASK, skip entire pool
        if(exclude) |exc| {
            for(exc) |exc_comp| {
                const exc_bit = MaskManager.Comptime.componentToBit(exc_comp);
                if(MaskManager.maskContains(pool_type.REQ_MASK, exc_bit)) {
                    excluded = true;
                    break;
                }
                // If excluded component is in pool_mask but not REQ_MASK,
                // pool still matches but needs Lookup access
                if(MaskManager.maskContains(pool_type.pool_mask, exc_bit)) {
                    req_match = false;
                }
            }
        }

        if(excluded) {
            continue;
        }

        for(components) |component| {
            const component_bit = MaskManager.Comptime.componentToBit(component);
            const in_pool = MaskManager.maskContains(pool_type.pool_mask, component_bit);

            @setEvalBranchQuota(3000);

            if(!in_pool) {
                query_match = false;
                req_match = false;
                break;
            }

            if(req_match) {
                const contained_in_req = MaskManager.maskContains(pool_type.REQ_MASK, component_bit);
                if(!contained_in_req) {
                    req_match = false;
                }
            }
        }

        if(req_match or query_match) {
            matches[idx] = .{
                .pool_name = @enumFromInt(i),
                .access = if(req_match) .Direct else .Lookup,
            };
            idx += 1;
        }
    }
    return matches;
}

/// Generates a heterogeneous struct type with one field per matching pool.
/// Each field has its own PoolElementType with comptime POOL_NAME.
pub fn PoolElementsType(comptime config: QueryConfig) type {
    const matches = comptime findMatchingPools(config);
    var fields: [matches.len]StructField = undefined;

    for(matches, 0..) |match, i| {
        const ElemType = PoolElementType(match.pool_name, config);
        fields[i] = StructField{
            .name = @tagName(match.pool_name),
            .type = ElemType,
            .alignment = @alignOf(ElemType),
            .default_value_ptr = null,
            .is_comptime = false,
        };
    }

    return @Type(.{
        .@"struct" = .{
            .fields = &fields,
            .layout = .auto,
            .is_tuple = false,
            .backing_integer = null,
            .decls = &.{},
        }
    });
}

/// Returns an initialized PoolElementsType instance with access modes set
pub fn findPoolElements(comptime config: QueryConfig) PoolElementsType(config) {
    const matches = comptime findMatchingPools(config);
    var result: PoolElementsType(config) = undefined;

    inline for(matches) |match| {
        const field_name = @tagName(match.pool_name);
        @field(result, field_name) = .{
            .access = match.access,
            .archetype_indices = .{},
            .sparse_cache = .{},
        };
    }

    return result;
}
