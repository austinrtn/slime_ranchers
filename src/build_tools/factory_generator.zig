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
        std.debug.print("Usage: zig build factory -- <FactoryName>\n", .{});
        return;
    };

    // Get factory name from user
    const factory_name = args.next() orelse {
        std.debug.print("\nError: No factory name provided.\n", .{});
        std.debug.print("Usage: zig build factory -- <FactoryName>\n", .{});
        return;
    };

    // Build paths
    const factories_dir = try std.fs.path.join(allocator, &.{ project_dir, "src", "factories" });
    defer allocator.free(factories_dir);

    const file_name = try std.mem.concat(allocator, u8, &.{ factory_name, ".zig" });
    defer allocator.free(file_name);

    const file_path = try std.fs.path.join(allocator, &.{ factories_dir, file_name });
    defer allocator.free(file_path);

    // Create factories directory if it doesn't exist
    std.fs.cwd().makePath(factories_dir) catch {};

    // Check if file already exists
    if (std.fs.cwd().access(file_path, .{})) |_| {
        std.debug.print("\nError: Factory '{s}' already exists at {s}\n", .{ factory_name, file_path });
        return;
    } else |_| {}

    // Generate factory template
    const template_fmt = "const std = @import(\"std\");\n" ++
        "const Prescient = @import(\"../ecs/Prescient.zig\").Prescient;\n" ++
        "const Entity = Prescient.Entity;\n" ++
        "\n" ++
        "pub const {s} = struct {{\n" ++
        "    const Self = @This();\n" ++
        "\n" ++
        "    prescient: *Prescient,\n" ++
        "\n" ++
        "    pub fn init() !Self {{\n" ++
        "        return .{{\n" ++
        "            .prescient = try Prescient.getPrescient(),\n" ++
        "        }};\n" ++
        "    }}\n" ++
        "\n" ++
        "    pub fn spawn(self: *Self) !Entity {{\n" ++
        "        var pool = try self.prescient.getPool(.GeneralPool);\n" ++
        "        return try pool.createEntity(.{{\n" ++
        "              //Add components here:\n" ++
        "              // .Position = .{{.x = 0, .y = 0}},\n" ++
        "              // .Velocity = .{{.dx = 1, .dy = 1}},\n" ++
        "        }});\n" ++
        "    }}\n" ++
        "}};\n" ++
        "\n";
    const template = try std.fmt.allocPrint(allocator, template_fmt, .{factory_name});
    defer allocator.free(template);

    // Write the file
    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();
    try file.writeAll(template);

    std.debug.print("\nFactory created: {s}\n", .{factory_name});
    std.debug.print("{s}\n", .{file_path});
    std.debug.print("\nRun 'zig build registry' to regenerate FactoryRegistry.zig\n\n", .{});
}
