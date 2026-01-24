const std = @import("std");
const SR = @import("../registries/SystemRegistry.zig");
const CR = @import("../registries/ComponentRegistry.zig");

/// Bitmask type for dependency tracking - O(1) operations instead of O(d^2) array appends
pub fn DependencyMask(comptime n: usize) type {
    return if (n <= 64) u64 else if (n <= 128) u128 else @compileError("Too many systems for bitmask (max 128)");
}

fn setBit(comptime T: type, mask: T, idx: usize) T {
    return mask | (@as(T, 1) << @intCast(idx));
}

fn hasBit(comptime T: type, mask: T, idx: usize) bool {
    return (mask & (@as(T, 1) << @intCast(idx))) != 0;
}

/// Extracts read/write component bitmasks from a system's queries and indirect declarations
pub fn SystemDependencyInfo(comptime SystemType: type) type {
    return struct {
        const CMask = ComponentMask();

        // Combined masks: query access + indirect access
        pub const read_mask = extractReadMask(SystemType);
        pub const write_mask = extractWriteMask(SystemType);
        pub const has_queries = read_mask != 0 or write_mask != 0;

        fn extractReadMask(comptime T: type) CMask {
            var result: CMask = 0;

            // From queries
            if (@hasField(T, "queries")) {
                const QueriesType = @TypeOf(@as(T, undefined).queries);
                inline for (std.meta.fields(QueriesType)) |field| {
                    const QueryType = field.type;
                    if (@hasDecl(QueryType, "READ_COMPONENTS")) {
                        result |= componentListToMask(QueryType.READ_COMPONENTS);
                    }
                }
            }

            // From indirect_reads declaration
            if (@hasDecl(T, "indirect_reads")) {
                result |= componentListToMask(T.indirect_reads);
            }

            return result;
        }

        fn extractWriteMask(comptime T: type) CMask {
            var result: CMask = 0;

            // From queries
            if (@hasField(T, "queries")) {
                const QueriesType = @TypeOf(@as(T, undefined).queries);
                inline for (std.meta.fields(QueriesType)) |field| {
                    const QueryType = field.type;
                    if (@hasDecl(QueryType, "WRITE_COMPONENTS")) {
                        result |= componentListToMask(QueryType.WRITE_COMPONENTS);
                    }
                }
            }

            // From indirect_writes declaration
            if (@hasDecl(T, "indirect_writes")) {
                result |= componentListToMask(T.indirect_writes);
            }

            return result;
        }
    };
}

/// Component bitmask for O(1) overlap checking
pub fn ComponentMask() type {
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
fn shouldRunBefore(a_write_mask: anytype, b_read_mask: anytype) bool {
    return (a_write_mask & b_read_mask) != 0;
}

/// Check if two systems have a write-write conflict - O(1)
fn hasWriteConflict(a_write_mask: anytype, b_write_mask: anytype) bool {
    return (a_write_mask & b_write_mask) != 0;
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

// ============================================================================
// Runtime Sorting Support
// ============================================================================

/// Metadata for each system - computed at comptime, used at runtime for sorting
pub fn SystemMetadata(comptime n: usize) type {
    const CMask = ComponentMask();
    const DMask = DependencyMask(n);

    return struct {
        read_mask: CMask,
        write_mask: CMask,
        runs_before_mask: DMask, // bitmask of systems this must run before
        runs_after_mask: DMask, // bitmask of systems that must run before this one
        has_queries: bool,
    };
}

/// Build metadata array at comptime - O(n) with no deeply nested loops
pub fn buildSystemMetadata(comptime systems: []const SR.SystemName) [systems.len]SystemMetadata(systems.len) {
    const n = systems.len;
    const DMask = DependencyMask(n);

    var result: [n]SystemMetadata(n) = undefined;

    // First pass: extract masks and runs_before declarations
    inline for (systems, 0..) |sys, i| {
        const SystemType = SR.getTypeByName(sys);
        const info = SystemDependencyInfo(SystemType);

        result[i] = .{
            .read_mask = info.read_mask,
            .write_mask = info.write_mask,
            .runs_before_mask = 0,
            .runs_after_mask = 0,
            .has_queries = info.has_queries,
        };

        // Build runs_before mask from declaration
        if (@hasDecl(SystemType, "runs_before")) {
            inline for (SystemType.runs_before) |target| {
                inline for (systems, 0..) |other_sys, j| {
                    if (other_sys == target) {
                        result[i].runs_before_mask = setBit(DMask, result[i].runs_before_mask, j);
                    }
                }
            }
        }
    }

    // Second pass: build runs_after masks (transpose of runs_before)
    inline for (0..n) |i| {
        inline for (0..n) |j| {
            if (hasBit(DMask, result[j].runs_before_mask, i)) {
                result[i].runs_after_mask = setBit(DMask, result[i].runs_after_mask, j);
            }
        }
    }

    return result;
}

/// Detect write-write conflicts at comptime - keeps compile errors for conflicts
pub fn detectWriteWriteConflicts(comptime systems: []const SR.SystemName, comptime metadata: []const SystemMetadata(systems.len)) void {
    const n = systems.len;
    const DMask = DependencyMask(n);

    inline for (0..n) |i| {
        inline for (i + 1..n) |j| {
            // O(1) write-write conflict check using bitmasks
            if (hasWriteConflict(metadata[i].write_mask, metadata[j].write_mask)) {
                // O(1) runs_before check using bitmasks
                const i_before_j = hasBit(DMask, metadata[i].runs_before_mask, j);
                const j_before_i = hasBit(DMask, metadata[j].runs_before_mask, i);

                if (!i_before_j and !j_before_i) {
                    // Get conflicting component name for error message
                    const conflict_mask = metadata[i].write_mask & metadata[j].write_mask;
                    const comp_name = getComponentNameFromMask(conflict_mask);
                    @compileError("Write-write conflict: Systems '" ++ @tagName(systems[i]) ++ "' and '" ++ @tagName(systems[j]) ++ "' both write to component '" ++ comp_name ++ "'. Add 'pub const runs_before = &.{." ++ @tagName(systems[j]) ++ "};' to " ++ @tagName(systems[i]) ++ " or vice versa.");
                }
            }
        }
    }
}

/// Runtime topological sort using Kahn's algorithm
/// Sorts systems without queries first, then systems with queries in dependency order
pub fn sortSystemsRuntime(
    comptime n: usize,
    metadata: []const SystemMetadata(n),
    out_order: []usize,
) error{DependencyCycle}!void {
    const DMask = DependencyMask(n);

    // First, collect systems without queries (they go first)
    var no_query_count: usize = 0;
    var with_query_indices: [n]usize = undefined;
    var with_query_count: usize = 0;

    for (metadata, 0..) |meta, i| {
        if (!meta.has_queries) {
            out_order[no_query_count] = i;
            no_query_count += 1;
        } else {
            with_query_indices[with_query_count] = i;
            with_query_count += 1;
        }
    }

    // Build runtime dependency graph for systems with queries
    var dependencies: [n]DMask = .{0} ** n;
    for (0..with_query_count) |wi| {
        const i = with_query_indices[wi];
        // Start with explicit runs_after dependencies
        dependencies[i] = metadata[i].runs_after_mask;

        // Add component-based dependencies
        for (0..with_query_count) |wj| {
            const j = with_query_indices[wj];
            if (i == j) continue;

            const j_bit: DMask = @as(DMask, 1) << @intCast(j);

            // j writes something i reads -> i depends on j
            // Unless blocked by i having runs_before j
            const is_blocked = hasBit(DMask, metadata[i].runs_before_mask, j);
            if (!is_blocked and shouldRunBefore(metadata[j].write_mask, metadata[i].read_mask)) {
                dependencies[i] |= j_bit;
            }
        }

        // Only keep dependencies on systems with queries (others are already placed first)
        var with_query_mask: DMask = 0;
        for (0..with_query_count) |wk| {
            with_query_mask |= @as(DMask, 1) << @intCast(with_query_indices[wk]);
        }
        dependencies[i] &= with_query_mask;
    }

    // Kahn's algorithm for systems with queries
    var placed: DMask = 0;
    var output_idx: usize = no_query_count;

    while (output_idx < n) {
        var found = false;

        // Find a system with all dependencies satisfied
        for (0..with_query_count) |wi| {
            const candidate = with_query_indices[wi];
            const candidate_bit: DMask = @as(DMask, 1) << @intCast(candidate);

            if ((placed & candidate_bit) != 0) continue; // already placed

            // Check if all dependencies are placed
            if ((dependencies[candidate] & ~placed) == 0) {
                out_order[output_idx] = candidate;
                output_idx += 1;
                placed |= candidate_bit;
                found = true;
                break;
            }
        }

        if (!found) {
            return error.DependencyCycle;
        }
    }
}
