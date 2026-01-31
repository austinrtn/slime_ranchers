const std = @import("std");
const metadata = @import("SystemMetadata");

const Args = struct {
    filter: ?[][]const u8 = null,
    show_stats: bool = false,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *@This()) void {
        if (self.filter) |f| {
            for (f) |name| {
                self.allocator.free(name);
            }
            self.allocator.free(f);
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command-line arguments
    var args = try parseArgs(allocator);
    defer args.deinit();

    // Handle empty registry
    if (metadata.all_metadata.len == 0) {
        std.debug.print("\n=== SYSTEM GRAPH ===\n\n", .{});
        std.debug.print("No systems found in registry.\n", .{});
        std.debug.print("\nAdd systems to src/systems/ and run 'zig build registry'\n\n", .{});
        return;
    }

    std.debug.print("\n", .{});

    // Section 1: Execution order
    try printExecutionOrder(metadata.all_metadata, args.filter);

    // Section 2: Dependency details
    try printDependencyDetails(metadata.all_metadata, args.filter);

    // Section 3: Write-write conflicts
    try printWriteConflicts(metadata.all_metadata);

    // Section 4: Component statistics (if --stats)
    if (args.show_stats) {
        try printComponentStats(metadata.all_metadata, allocator);
    }
}

fn parseArgs(allocator: std.mem.Allocator) !Args {
    var result = Args{
        .allocator = allocator,
    };

    var arg_iter = try std.process.argsWithAllocator(allocator);
    defer arg_iter.deinit();

    // Skip program name
    _ = arg_iter.next();

    var filter_list: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (filter_list.items) |item| allocator.free(item);
        filter_list.deinit(allocator);
    }

    while (arg_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--stats")) {
            result.show_stats = true;
        } else if (std.mem.eql(u8, arg, "--filter")) {
            // Next arg should be comma-separated list of system names
            if (arg_iter.next()) |filter_arg| {
                var tokens = std.mem.tokenizeScalar(u8, filter_arg, ',');
                while (tokens.next()) |token| {
                    const trimmed = std.mem.trim(u8, token, " \t");
                    try filter_list.append(allocator, try allocator.dupe(u8, trimmed));
                }
            }
        } else if (std.mem.eql(u8, arg, "--help")) {
            printHelp();
            std.process.exit(0);
        }
    }

    if (filter_list.items.len > 0) {
        result.filter = try filter_list.toOwnedSlice(allocator);
    } else {
        filter_list.deinit(allocator);
    }

    return result;
}

fn printHelp() void {
    std.debug.print(
        \\
        \\System Graph - Display system execution order and dependencies
        \\
        \\USAGE:
        \\    zig build system-graph [OPTIONS]
        \\
        \\OPTIONS:
        \\    --filter <systems>    Comma-separated list of system names to display
        \\    --stats              Show component usage statistics
        \\    --help               Display this help message
        \\
        \\EXAMPLES:
        \\    zig build system-graph
        \\    zig build system-graph -- --filter SystemA,SystemB
        \\    zig build system-graph -- --stats
        \\
        \\
    , .{});
}

fn matchesFilter(system_name: []const u8, filter: ?[][]const u8) bool {
    if (filter == null) return true;

    for (filter.?) |f| {
        if (std.mem.eql(u8, system_name, f)) return true;
    }
    return false;
}

fn printExecutionOrder(systems: []const metadata.SystemMetadata, filter: ?[][]const u8) !void {
    std.debug.print("=== SYSTEM EXECUTION ORDER ===\n\n", .{});

    var order: usize = 1;
    var current_phase: ?[]const u8 = null;

    // Print systems in pre-computed execution order, grouped by phase
    for (metadata.execution_order) |idx| {
        const sys = systems[idx];
        if (!matchesFilter(sys.name, filter)) continue;

        // Print phase header when phase changes
        if (current_phase == null or !std.mem.eql(u8, current_phase.?, sys.phase)) {
            if (current_phase != null) std.debug.print("\n", .{});
            std.debug.print("--- {s} ---\n", .{sys.phase});
            current_phase = sys.phase;
        }

        if (sys.has_queries) {
            std.debug.print("{d}. {s}          [has queries]\n", .{ order, sys.name });
        } else {
            std.debug.print("{d}. {s}\n", .{ order, sys.name });
        }
        order += 1;
    }

    std.debug.print("\n", .{});
}

fn printDependencyDetails(systems: []const metadata.SystemMetadata, filter: ?[][]const u8) !void {
    std.debug.print("=== DEPENDENCY DETAILS ===\n\n", .{});

    var any_printed = false;

    for (systems) |sys| {
        if (!matchesFilter(sys.name, filter)) continue;
        any_printed = true;

        std.debug.print("{s} (phase: {s}):\n", .{ sys.name, sys.phase });

        // Read components
        std.debug.print("  Reads:  ", .{});
        if (sys.reads.len == 0) {
            std.debug.print("(none)", .{});
        } else {
            for (sys.reads, 0..) |comp, idx| {
                if (idx > 0) std.debug.print(", ", .{});
                std.debug.print("{s}", .{comp});
            }
        }
        std.debug.print("\n", .{});

        // Write components
        std.debug.print("  Writes: ", .{});
        if (sys.writes.len == 0) {
            std.debug.print("(none)", .{});
        } else {
            for (sys.writes, 0..) |comp, idx| {
                if (idx > 0) std.debug.print(", ", .{});
                std.debug.print("{s}", .{comp});
            }
        }
        std.debug.print("\n", .{});

        // Dependencies
        std.debug.print("  Must run AFTER:\n", .{});

        var has_dependencies = false;

        // Explicit runs_after
        for (sys.runs_after) |dep| {
            std.debug.print("    • {s} (explicit runs_after)\n", .{dep});
            has_dependencies = true;
        }

        // Component-based dependencies (other systems that write what this reads)
        for (systems) |other_sys| {
            if (std.mem.eql(u8, sys.name, other_sys.name)) continue;

            // Skip if it's already an explicit dependency
            var is_explicit = false;
            for (sys.runs_after) |dep| {
                if (std.mem.eql(u8, dep, other_sys.name)) {
                    is_explicit = true;
                    break;
                }
            }
            if (is_explicit) continue;

            // Check if other_sys is in sys.runs_before (would override component dependency)
            var is_blocked = false;
            for (sys.runs_before) |before| {
                if (std.mem.eql(u8, before, other_sys.name)) {
                    is_blocked = true;
                    break;
                }
            }
            if (is_blocked) continue;

            // Find overlapping components (other writes what this reads)
            var overlapping: std.ArrayList([]const u8) = .empty;
            defer overlapping.deinit(std.heap.page_allocator);

            for (other_sys.writes) |write_comp| {
                for (sys.reads) |read_comp| {
                    if (std.mem.eql(u8, write_comp, read_comp)) {
                        try overlapping.append(std.heap.page_allocator, write_comp);
                    }
                }
            }

            if (overlapping.items.len > 0) {
                std.debug.print("    • {s} (component dependency: {s} writes ", .{ other_sys.name, other_sys.name });
                for (overlapping.items, 0..) |comp, idx| {
                    if (idx > 0) std.debug.print(", ", .{});
                    std.debug.print("{s}", .{comp});
                }
                std.debug.print(")\n", .{});
                has_dependencies = true;
            }
        }

        if (!has_dependencies) {
            std.debug.print("    (no dependencies)\n", .{});
        }

        std.debug.print("\n", .{});
    }

    if (!any_printed) {
        std.debug.print("(No systems match filter)\n\n", .{});
    }
}

fn printWriteConflicts(systems: []const metadata.SystemMetadata) !void {
    std.debug.print("=== WRITE-WRITE CONFLICTS ===\n", .{});
    std.debug.print("(Only checked within same phase - systems in different phases run sequentially)\n\n", .{});

    var conflicts_found = false;

    for (systems, 0..) |sys_i, i| {
        for (systems[i + 1 ..]) |sys_j| {
            // Skip if systems are in different phases (they run sequentially)
            if (!std.mem.eql(u8, sys_i.phase, sys_j.phase)) {
                continue;
            }

            // Find write-write conflicts
            var conflicts: std.ArrayList([]const u8) = .empty;
            defer conflicts.deinit(std.heap.page_allocator);

            for (sys_i.writes) |write_i| {
                for (sys_j.writes) |write_j| {
                    if (std.mem.eql(u8, write_i, write_j)) {
                        try conflicts.append(std.heap.page_allocator, write_i);
                    }
                }
            }

            if (conflicts.items.len > 0) {
                // Check if ordered
                var i_before_j = false;
                var j_before_i = false;

                for (sys_i.runs_before) |before| {
                    if (std.mem.eql(u8, before, sys_j.name)) {
                        i_before_j = true;
                        break;
                    }
                }

                for (sys_j.runs_before) |before| {
                    if (std.mem.eql(u8, before, sys_i.name)) {
                        j_before_i = true;
                        break;
                    }
                }

                if (!i_before_j and !j_before_i) {
                    conflicts_found = true;

                    std.debug.print("✗ CONFLICT: {s} and {s} (both in phase '{s}') both write ", .{ sys_i.name, sys_j.name, sys_i.phase });
                    for (conflicts.items, 0..) |comp, idx| {
                        if (idx > 0) std.debug.print(", ", .{});
                        std.debug.print("{s}", .{comp});
                    }
                    std.debug.print("\n", .{});
                    std.debug.print("  Fix: Add 'pub const runs_before = &.{{.{s}}};' to {s}\n", .{ sys_j.name, sys_i.name });
                    std.debug.print("\n", .{});
                }
            }
        }
    }

    if (!conflicts_found) {
        std.debug.print("✓ No write-write conflicts detected\n\n", .{});
    }
}

fn printComponentStats(systems: []const metadata.SystemMetadata, allocator: std.mem.Allocator) !void {
    std.debug.print("=== COMPONENT USAGE STATISTICS ===\n\n", .{});

    const ComponentStats = struct {
        readers: std.ArrayList([]const u8),
        writers: std.ArrayList([]const u8),
    };

    // Map component names to their stats
    var stats_map = std.StringHashMap(ComponentStats).init(allocator);
    defer {
        var iter = stats_map.valueIterator();
        while (iter.next()) |stat| {
            stat.readers.deinit(allocator);
            stat.writers.deinit(allocator);
        }
        stats_map.deinit();
    }

    // Collect all unique component names
    var all_components = std.StringHashMap(void).init(allocator);
    defer all_components.deinit();

    for (systems) |sys| {
        for (sys.reads) |comp| {
            try all_components.put(comp, {});
        }
        for (sys.writes) |comp| {
            try all_components.put(comp, {});
        }
    }

    // Initialize stats for all components
    var comp_iter = all_components.keyIterator();
    while (comp_iter.next()) |comp_name| {
        try stats_map.put(comp_name.*, .{
            .readers = .empty,
            .writers = .empty,
        });
    }

    // Collect stats
    for (systems) |sys| {
        for (sys.reads) |comp| {
            var stat = stats_map.getPtr(comp).?;
            try stat.readers.append(allocator, sys.name);
        }

        for (sys.writes) |comp| {
            var stat = stats_map.getPtr(comp).?;
            try stat.writers.append(allocator, sys.name);
        }
    }

    // Print stats for each component
    var max_readers: usize = 0;
    var max_readers_comp: ?[]const u8 = null;
    var max_writers: usize = 0;
    var max_writers_comp: ?[]const u8 = null;
    var unused_count: usize = 0;

    var stats_iter = stats_map.iterator();
    while (stats_iter.next()) |entry| {
        const comp_name = entry.key_ptr.*;
        const stat = entry.value_ptr.*;

        std.debug.print("{s}:\n", .{comp_name});

        // Readers
        std.debug.print("  Read by:  ", .{});
        if (stat.readers.items.len == 0) {
            std.debug.print("(none)", .{});
        } else {
            for (stat.readers.items, 0..) |sys, idx| {
                if (idx > 0) std.debug.print(", ", .{});
                std.debug.print("{s}", .{sys});
            }
        }
        std.debug.print("\n", .{});

        // Writers
        std.debug.print("  Written by: ", .{});
        if (stat.writers.items.len == 0) {
            std.debug.print("(none)", .{});
        } else {
            for (stat.writers.items, 0..) |sys, idx| {
                if (idx > 0) std.debug.print(", ", .{});
                std.debug.print("{s}", .{sys});
            }
        }
        std.debug.print("\n", .{});

        std.debug.print("  Total readers: {d}, Total writers: {d}\n", .{ stat.readers.items.len, stat.writers.items.len });

        // Check for warnings
        if (stat.writers.items.len > 0 and stat.readers.items.len == 0) {
            std.debug.print("  ⚠️  Written but never read\n", .{});
        }

        if (stat.readers.items.len == 0 and stat.writers.items.len == 0) {
            unused_count += 1;
        }

        // Track maximums
        if (stat.readers.items.len > max_readers) {
            max_readers = stat.readers.items.len;
            max_readers_comp = comp_name;
        }
        if (stat.writers.items.len > max_writers) {
            max_writers = stat.writers.items.len;
            max_writers_comp = comp_name;
        }

        std.debug.print("\n", .{});
    }

    // Summary
    const total_components = all_components.count();
    std.debug.print("Summary:\n", .{});
    std.debug.print("  Total components: {d}\n", .{total_components});

    if (max_readers_comp) |comp| {
        std.debug.print("  Most read: {s} ({d} readers)\n", .{ comp, max_readers });
    }

    if (max_writers_comp) |comp| {
        std.debug.print("  Most written: {s} ({d} writers)\n", .{ comp, max_writers });
    }

    if (unused_count > 0) {
        std.debug.print("  Unused (never read or written): {d} components\n", .{unused_count});
    }

    std.debug.print("\n", .{});
}
