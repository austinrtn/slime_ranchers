const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();
    
    // Skip executable name
    _ = args.next();

    // Get project directory (passed from build.zig)
    const project_dir = args.next() orelse {
        std.debug.print("\nError: No project directory provided.\n", .{});
        std.debug.print("Usage: zig build system -- <SystemName>\n", .{});
        return;
    };

    // Get system name from user
    const system_name = args.next() orelse {
        std.debug.print("\nError: No system name provided.\n", .{});
        std.debug.print("Usage: zig build system -- <SystemName>\n", .{});
        return;
    };

    // Build paths
    const systems_dir = try std.fs.path.join(allocator, &.{ project_dir, "src", "systems" });
    defer allocator.free(systems_dir);

    const file_name = try std.mem.concat(allocator, u8, &.{ system_name, ".zig" });
    defer allocator.free(file_name);

    const file_path = try std.fs.path.join(allocator, &.{ systems_dir, file_name });
    defer allocator.free(file_path);

    // Create systems directory if it doesn't exist
    std.fs.cwd().makePath(systems_dir) catch {};

    // Check if file already exists
    if (std.fs.cwd().access(file_path, .{})) |_| {
        std.debug.print("\nError: System '{s}' already exists at {s}\n", .{ system_name, file_path });
        return;
    } else |_| {}

    // Generate system template
    const template = try std.fmt.allocPrint(allocator,
        \\const std = @import("std");
        \\const Prescient = @import("../ecs/Prescient.zig").Prescient;
        \\const SR = @import("../registries/SystemRegistry.zig");
        \\const Query = @import("../ecs/Query.zig").QueryType;
        \\const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;
        \\
        \\pub const {s} = struct {{
        \\    const Self = @This();
        \\    pub const enabled = true;
        \\    // Optional: resolve write-write conflicts with other systems
        \\    // pub const runs_before = &[_]SR.SystemName{{ .OtherSystem }};
        \\
        \\    // Optional: declare indirect component access (through entity references)
        \\    // pub const indirect_reads = &.{{}};
        \\    // pub const indirect_writes = &.{{}};
        \\
        \\    allocator: std.mem.Allocator,
        \\    active: bool = true,
        \\    queries: struct {{
        \\        // Example query with read/write separation:
        \\        // movement: Query(.{{
        \\        //     .read = &.{{.Velocity}},   // *const T - cannot mutate
        \\        //     .write = &.{{.Position}},  // *T - can mutate (implies read access)
        \\        // }}),
        \\    }},
        \\
        \\    pub fn update(self: *Self) !void {{
        \\        _ = self;
        \\        // forEach (zero-allocation iteration):
        \\        // try self.queries.movement.forEach(self, struct {{
        \\        //     pub fn run(ctx: anytype, c: anytype) !bool {{
        \\        //         // c.Velocity is *const Velocity (read-only)
        \\        //         // c.Position is *Position (mutable)
        \\        //         c.Position.x += c.Velocity.dx;
        \\        //         return true;  // continue (return false to stop iteration)
        \\        //     }}
        \\        // }});
        \\    }}
        \\}};
        \\
    , .{system_name});
    defer allocator.free(template);

    // Write the file
    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();
    try file.writeAll(template);

    std.debug.print("\nSystem created: {s}\n", .{system_name});
    std.debug.print("{s}\n", .{file_path});
    std.debug.print("\nRun 'zig build registry' to regenerate SystemRegistry.zig\n\n", .{});
}
