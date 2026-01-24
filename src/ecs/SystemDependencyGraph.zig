const std = @import("std");
const SR = @import("../registries/SystemRegistry.zig");
const CR = @import("../registries/ComponentRegistry.zig");

/// Bitmask type for dependency tracking - O(1) operations instead of O(d²) array appends
fn DependencyMask(comptime n: usize) type {
    return if (n <= 64) u64 else if (n <= 128) u128 else @compileError("Too many systems for bitmask (max 128)");
}

fn setBit(comptime T: type, mask: T, idx: usize) T {
    return mask | (@as(T, 1) << @intCast(idx));
}

fn hasBit(comptime T: type, mask: T, idx: usize) bool {
    return (mask & (@as(T, 1) << @intCast(idx))) != 0;
}

/// Extracts read/write component bitmasks from a system's queries - O(q) instead of O(q×c²)
pub fn SystemDependencyInfo(comptime SystemType: type) type {
    return struct {
        const CMask = ComponentMask();

        // Use bitmasks directly - O(1) merge via bitwise OR instead of O(c²) nested loops
        pub const read_mask = extractReadMask(SystemType);
        pub const write_mask = extractWriteMask(SystemType);
        pub const has_queries = read_mask != 0 or write_mask != 0;

        fn extractReadMask(comptime T: type) CMask {
            if (!@hasField(T, "queries")) return 0;

            const QueriesType = @TypeOf(@as(T, undefined).queries);
            var result: CMask = 0;

            inline for (std.meta.fields(QueriesType)) |field| {
                const QueryType = field.type;
                if (@hasDecl(QueryType, "READ_COMPONENTS")) {
                    // O(c) to convert list to mask, O(1) to merge via OR
                    result |= componentListToMask(QueryType.READ_COMPONENTS);
                }
            }
            return result;
        }

        fn extractWriteMask(comptime T: type) CMask {
            if (!@hasField(T, "queries")) return 0;

            const QueriesType = @TypeOf(@as(T, undefined).queries);
            var result: CMask = 0;

            inline for (std.meta.fields(QueriesType)) |field| {
                const QueryType = field.type;
                if (@hasDecl(QueryType, "WRITE_COMPONENTS")) {
                    // O(c) to convert list to mask, O(1) to merge via OR
                    result |= componentListToMask(QueryType.WRITE_COMPONENTS);
                }
            }
            return result;
        }
    };
}

/// Component bitmask for O(1) overlap checking
fn ComponentMask() type {
    const num_components = std.meta.fields(CR.ComponentName).len;
    return if (num_components <= 64) u64 else if (num_components <= 128) u128 else @compileError("Too many components");
}

fn componentListToMask(comptime components: []const CR.ComponentName) ComponentMask() {
    const Mask = ComponentMask();
    var result: Mask = 0;
    for (components) |comp| {
        result |= @as(Mask, 1) << @intFromEnum(comp);
    }
    return result;
}

/// Check if system A should run before system B (A writes something B reads) - O(1)
fn shouldRunBefore(comptime a_write_mask: ComponentMask(), comptime b_read_mask: ComponentMask()) bool {
    return (a_write_mask & b_read_mask) != 0;
}

/// Check if two systems have a write-write conflict - O(1)
fn hasWriteConflict(comptime a_write_mask: ComponentMask(), comptime b_write_mask: ComponentMask()) bool {
    return (a_write_mask & b_write_mask) != 0;
}


/// Pre-computed system info for O(1) lookups
fn SystemInfo(comptime systems: []const SR.SystemName) type {
    return struct {
        const CMask = ComponentMask();
        const DMask = DependencyMask(systems.len);
        read_masks: [systems.len]CMask,
        write_masks: [systems.len]CMask,
        runs_before_masks: [systems.len]DMask,      // i runs before these systems
        runs_after_masks: [systems.len]DMask,       // these systems run before i (transposed)
    };
}

fn buildSystemInfo(comptime systems: []const SR.SystemName) SystemInfo(systems) {
    const CMask = ComponentMask();
    const DMask = DependencyMask(systems.len);

    var read_masks: [systems.len]CMask = undefined;
    var write_masks: [systems.len]CMask = undefined;
    var runs_before_masks: [systems.len]DMask = .{0} ** systems.len;
    var runs_after_masks: [systems.len]DMask = .{0} ** systems.len;

    inline for (0..systems.len) |i| {
        const SystemType = SR.getTypeByName(systems[i]);
        const info = SystemDependencyInfo(SystemType);
        read_masks[i] = info.read_mask;
        write_masks[i] = info.write_mask;

        // Build runs_before mask AND its transpose (runs_after)
        if (@hasDecl(SystemType, "runs_before")) {
            inline for (SystemType.runs_before) |target| {
                inline for (0..systems.len) |j| {
                    if (systems[j] == target) {
                        runs_before_masks[i] = setBit(DMask, runs_before_masks[i], j);
                        runs_after_masks[j] = setBit(DMask, runs_after_masks[j], i);
                    }
                }
            }
        }
    }

    return .{
        .read_masks = read_masks,
        .write_masks = write_masks,
        .runs_before_masks = runs_before_masks,
        .runs_after_masks = runs_after_masks,
    };
}

/// Builds dependency graph using bitmasks for O(1) operations
/// Returns struct with:
/// - dependencies[i]: bitmask of systems that must run before i
/// - dependents[i]: bitmask of systems that depend on i (must run after i)
fn buildDependencyGraph(comptime systems: []const SR.SystemName, comptime sys_info: SystemInfo(systems)) struct {
    const Mask = DependencyMask(systems.len);
    dependencies: [systems.len]Mask,
    dependents: [systems.len]Mask,
} {
    const Mask = DependencyMask(systems.len);
    var dependencies: [systems.len]Mask = .{0} ** systems.len;
    var dependents: [systems.len]Mask = .{0} ** systems.len;

    // Compute dependencies and dependents in a single O(n²) pass
    inline for (0..systems.len) |i| {
        const i_bit = @as(Mask, 1) << @intCast(i);
        const blocked = sys_info.runs_before_masks[i];

        // Start with explicit runs_after dependencies
        dependencies[i] = sys_info.runs_after_masks[i];

        inline for (0..systems.len) |j| {
            if (i == j) continue;

            const j_bit = @as(Mask, 1) << @intCast(j);

            // Check if this is an explicit runs_after dependency (j runs before i)
            // These are already in dependencies[i], so add to dependents[j]
            if ((sys_info.runs_after_masks[i] & j_bit) != 0) {
                dependents[j] |= i_bit;
            }

            // Component dependency: j writes something i reads (j → i)
            // Only add if NOT blocked by i having runs_before j
            const is_blocked = (blocked & j_bit) != 0;
            if (!is_blocked and shouldRunBefore(sys_info.write_masks[j], sys_info.read_masks[i])) {
                dependencies[i] |= j_bit;
                dependents[j] |= i_bit;
            }
        }
    }

    return .{
        .dependencies = dependencies,
        .dependents = dependents,
    };
}

/// Detects unresolved write-write conflicts using pre-computed bitmasks
fn detectWriteWriteConflicts(comptime systems: []const SR.SystemName, comptime sys_info: SystemInfo(systems)) void {
    const Mask = DependencyMask(systems.len);

    inline for (0..systems.len) |i| {
        inline for (i + 1..systems.len) |j| {
            // O(1) write-write conflict check using bitmasks
            if (hasWriteConflict(sys_info.write_masks[i], sys_info.write_masks[j])) {
                // O(1) runs_before check using bitmasks
                const i_before_j = hasBit(Mask, sys_info.runs_before_masks[i], j);
                const j_before_i = hasBit(Mask, sys_info.runs_before_masks[j], i);

                if (!i_before_j and !j_before_i) {
                    // Get conflicting component name for error message
                    const conflict_mask = sys_info.write_masks[i] & sys_info.write_masks[j];
                    const comp_name = getComponentNameFromMask(conflict_mask);
                    @compileError("Write-write conflict: Systems '" ++ @tagName(systems[i]) ++ "' and '" ++ @tagName(systems[j]) ++ "' both write to component '" ++ comp_name ++ "'. Add 'pub const runs_before = &.{." ++ @tagName(systems[j]) ++ "};' to " ++ @tagName(systems[i]) ++ " or vice versa.");
                }
            }
        }
    }
}

fn getComponentNameFromMask(comptime mask: ComponentMask()) []const u8 {
    // Find the first set bit and return its component name
    inline for (std.meta.fields(CR.ComponentName), 0..) |field, i| {
        if ((mask & (@as(ComponentMask(), 1) << i)) != 0) {
            return field.name;
        }
    }
    return "";
}

/// Topologically sorts systems using Kahn's algorithm with cycle detection
/// Uses bitmasks for efficient dependency tracking
fn topologicalSort(
    comptime systems: []const SR.SystemName,
    comptime Mask: type,
    comptime dependencies: [systems.len]Mask,
    comptime dependents: [systems.len]Mask,
) [systems.len]SR.SystemName {
    const n = systems.len;
    if (n == 0) return .{};

    // in_degree[i] = number of systems that must run before i (popcount of dependency mask)
    var in_deg: [n]usize = undefined;
    inline for (0..n) |i| {
        in_deg[i] = @popCount(dependencies[i]);
    }

    // Find all systems with no dependencies (in_degree = 0)
    var queue: [n]usize = undefined;
    var queue_start: usize = 0;
    var queue_end: usize = 0;

    inline for (0..n) |i| {
        if (in_deg[i] == 0) {
            queue[queue_end] = i;
            queue_end += 1;
        }
    }

    // Process queue
    var result: [n]SR.SystemName = undefined;
    var result_idx: usize = 0;
    var processed: [n]bool = .{false} ** n;

    // Note: We need to do this iteratively at comptime
    // Zig comptime doesn't support while loops with runtime-determined bounds well
    // So we'll use a fixed iteration count equal to n

    inline for (0..n) |_| {
        if (queue_start >= queue_end) break;

        const curr = queue[queue_start];
        queue_start += 1;
        processed[curr] = true;

        result[result_idx] = systems[curr];
        result_idx += 1;

        // For each system that depends on curr (check bits in dependents mask)
        inline for (0..n) |dependent| {
            if (hasBit(Mask, dependents[curr], dependent)) {
                if (processed[dependent]) continue;
                in_deg[dependent] -= 1;
                if (in_deg[dependent] == 0) {
                    queue[queue_end] = dependent;
                    queue_end += 1;
                }
            }
        }
    }

    if (result_idx != n) {
        // Cycle detected - find systems involved
        var cycle_systems: []const u8 = "";
        inline for (0..n) |i| {
            if (!processed[i]) {
                if (cycle_systems.len > 0) {
                    cycle_systems = cycle_systems ++ ", ";
                }
                cycle_systems = cycle_systems ++ @tagName(systems[i]);
            }
        }
        @compileError("Dependency cycle detected involving systems: " ++ cycle_systems);
    }

    return result;
}

/// Sorts systems without queries to the beginning
fn separateQuerySystems(comptime systems: []const SR.SystemName) struct {
    no_query: []const SR.SystemName,
    with_query: []const SR.SystemName,
} {
    var no_query_count: usize = 0;
    var with_query_count: usize = 0;

    inline for (systems) |sys| {
        const SystemType = SR.getTypeByName(sys);
        const info = SystemDependencyInfo(SystemType);
        if (info.has_queries) {
            with_query_count += 1;
        } else {
            no_query_count += 1;
        }
    }

    var no_query: [no_query_count]SR.SystemName = undefined;
    var with_query: [with_query_count]SR.SystemName = undefined;
    var no_idx: usize = 0;
    var with_idx: usize = 0;

    inline for (systems) |sys| {
        const SystemType = SR.getTypeByName(sys);
        const info = SystemDependencyInfo(SystemType);
        if (info.has_queries) {
            with_query[with_idx] = sys;
            with_idx += 1;
        } else {
            no_query[no_idx] = sys;
            no_idx += 1;
        }
    }

    const no_query_final = no_query;
    const with_query_final = with_query;

    return .{
        .no_query = &no_query_final,
        .with_query = &with_query_final,
    };
}

/// Main public API: sorts systems based on their dependencies
/// Systems without queries are placed at the beginning
/// Returns sorted array of system names
pub fn sortSystems(comptime systems: []const SR.SystemName) [systems.len]SR.SystemName {
    if (systems.len == 0) return .{};

    // Separate systems with and without queries
    const separated = separateQuerySystems(systems);

    // Pre-compute all system info once (O(n) instead of O(n²))
    const sys_info = buildSystemInfo(separated.with_query);

    // Detect write-write conflicts using pre-computed bitmasks
    detectWriteWriteConflicts(separated.with_query, sys_info);

    // Build dependency graph for systems with queries (uses bitmasks for O(1) ops)
    const graph = buildDependencyGraph(separated.with_query, sys_info);

    // Topologically sort systems with queries
    const Mask = DependencyMask(separated.with_query.len);
    const sorted_with_query = topologicalSort(
        separated.with_query,
        Mask,
        graph.dependencies,
        graph.dependents,
    );

    // Combine: no-query systems first, then sorted query systems
    var result: [systems.len]SR.SystemName = undefined;

    for (separated.no_query, 0..) |sys, i| {
        result[i] = sys;
    }

    for (sorted_with_query, separated.no_query.len..) |sys, i| {
        result[i] = sys;
    }

    return result;
}
