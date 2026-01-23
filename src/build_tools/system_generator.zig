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
        \\const ComponentRegistry = @import("../registries/ComponentRegistry.zig");
        \\const Query = @import("../ecs/Query.zig").QueryType;
        \\const PoolManager = @import("../ecs/PoolManager.zig").PoolManager;
        \\
        \\pub const {s} = struct {{
        \\    const Self = @This();
        \\
        \\    // Dependency declarations for compile-time system ordering
        \\    pub const reads = [_]type{{}};
        \\    pub const writes = [_]type{{}};
        \\
        \\    allocator: std.mem.Allocator,
        \\    active: bool = true,
        \\    queries: struct {{
        \\        // Example: movement: Query(.{{ .comps = &.{{.Position, .Velocity}} }}),
        \\    }},
        \\
        \\    pub fn update(self: *Self) !void {{
        \\        _ = self;
        \\        // forEach (zero-allocation iteration):
        \\        // try self.queries.movement.forEach(self, struct {{
        \\        //     pub fn run(data: anytype, c: anytype) !bool {{
        \\        //         c.Position.x += c.Velocity.dx * data.delta_time;
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
