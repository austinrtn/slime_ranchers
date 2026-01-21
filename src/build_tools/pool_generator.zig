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
        std.debug.print("Usage: zig build pool -- <PoolName>\n", .{});
        return;
    };

    // Get pool name from user
    const pool_name = args.next() orelse {
        std.debug.print("\nError: No pool name provided.\n", .{});
        std.debug.print("Usage: zig build pool -- <PoolName>\n", .{});
        return;
    };

    // Build paths
    const pools_dir = try std.fs.path.join(allocator, &.{ project_dir, "src", "pools" });
    defer allocator.free(pools_dir);

    const file_name = try std.mem.concat(allocator, u8, &.{ pool_name, ".zig" });
    defer allocator.free(file_name);

    const file_path = try std.fs.path.join(allocator, &.{ pools_dir, file_name });
    defer allocator.free(file_path);

    // Create pools directory if it doesn't exist
    std.fs.cwd().makePath(pools_dir) catch {};

    // Check if file already exists
    if (std.fs.cwd().access(file_path, .{})) |_| {
        std.debug.print("\nError: Pool '{s}' already exists at {s}\n", .{ pool_name, file_path });
        return;
    } else |_| {}

    // Generate pool template
    const template = try std.fmt.allocPrint(allocator,
        \\const std = @import("std");
        \\const EntityPool = @import("../ecs/EntityPool.zig").EntityPool;
        \\const CR = @import("../registries/ComponentRegistry.zig");
        \\const ComponentName = CR.ComponentName;
        \\
        \\// Define which components this pool supports
        \\const pool_components = &[_]ComponentName{{
        \\    // Add your components here, e.g.:
        \\    // .Position,
        \\    // .Velocity,
        \\}};
        \\
        \\const req_components = &[_]ComponentName{{
        \\    // Add your required components here, e.g.:
        \\    // .Position,
        \\    // .Velocity,
        \\}};
        \\
        \\pub const {s} = EntityPool(.{{
        \\    .name = .{s},
        \\    .components = pool_components,
        \\    .req = req_components,
        \\    .storage_strategy = .SPARSE,
        \\}});
        \\
    , .{ pool_name, pool_name });
    defer allocator.free(template);

    // Write the file
    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();
    try file.writeAll(template);

    std.debug.print("\nPool created: {s}\n", .{pool_name});
    std.debug.print("{s}\n", .{file_path});
    std.debug.print("\nRun 'zig build registry' to regenerate PoolRegistry.zig\n\n", .{});
}
