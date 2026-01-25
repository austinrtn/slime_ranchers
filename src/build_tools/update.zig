const std = @import("std");
const gh_link =  "https://raw.githubusercontent.com/austinrtn/Prescient/main/";

const root_files = [_][]const u8 {
    "build.zig",
};

const build_tools_dir = "src/build_tools/";
const build_tool_files = [_][]const u8{
    "update.zig",
    "FileWriter.zig",
    "registry_builder.zig",
    "system_generator.zig",
    "component_generator.zig",
    "pool_generator.zig",
    "raylib_installer.zig",
    "factory_generator.zig",
    "system_graph",
};

const source_files_dir = "src/ecs/";
const source_files = [_][]const u8{
    "ecs.zig",
    "EntityAssembler.zig",
    "EntityBuilder.zig",
    "EntityPool.zig",
    "MaskManager.zig",
    "MigrationQueue.zig",
    "PoolConfig.zig",
    "StorageStrategy.zig",
    "EntityOperationQueue.zig",
    "EntityManager.zig",
    "ArchetypePool.zig",
    "SparseSetPool.zig",
    "PoolInterface.zig",
    "PoolManager.zig",
    "SystemDependencyGraph.zig",
    "Prescient.zig",
    "Query.zig",
    "QueryTypes.zig",
    "SystemManager.zig",
};


pub fn main() !void {
    var args = std.process.args();
    _ = args.next(); 

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stdin_buffer: [512]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
    const stdin = &stdin_reader.interface;
    
    const root_dir = args.next() orelse return error.noRoot;

    try stdout.flush();
    try stdout.writeAll("\nAre you sure you want to update Prescient?\nDoing so may cause errors.\nConfirm update [y/n]: ");
    try stdout.flush();

    if (stdin.takeDelimiterExclusive('\n')) |line| {
        const char = std.ascii.toLower(line[0]);
        if(line.len != 1 or char != 'y') {
            try stdout.writeAll("\nInput not valid");
            try stdout.flush();
            return;
        }
    } else |err| switch (err) {
        error.EndOfStream => {},
        error.StreamTooLong => return err,
        error.ReadFailed => return err,
    }

    // FIX: Added root_files to the count
    const file_count: usize = root_files.len + build_tool_files.len + source_files.len;
    var files_completed: usize = 0;
    try stdout.writeAll("\nDownloading and Writing Files\n");
    try stdout.flush();

    // FIX: Added loop for root_files
    inline for(root_files) |file| {
        const link = gh_link ++ file;
        // FIX: Added "/" separator between root_dir and file
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{root_dir, file});
        defer allocator.free(path);

        try downloadFile(allocator, link, path);
        files_completed += 1;
        try drawProgressBar(stdout, files_completed, file_count, file);
    }

    inline for(build_tool_files) |file| {
        const link = gh_link ++ build_tools_dir ++ file;
        // FIX: Added "/" separator between root_dir and build_tools_dir
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}{s}", .{root_dir, build_tools_dir, file});
        defer allocator.free(path);

        try downloadFile(allocator, link, path);
        files_completed += 1;
        try drawProgressBar(stdout, files_completed, file_count, file);
    }

    // FIX: Added missing loop for source_files
    inline for(source_files) |file| {
        const link = gh_link ++ source_files_dir ++ file;
        // FIX: Added "/" separator between root_dir and source_files_dir
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}{s}", .{root_dir, source_files_dir, file});
        defer allocator.free(path);

        try downloadFile(allocator, link, path);
        files_completed += 1;
        try drawProgressBar(stdout, files_completed, file_count, file);
    }

    try stdout.writeAll("\n✓ Update complete!\n");
    try stdout.flush();
}

fn drawProgressBar(
    stdout: *std.Io.Writer,
    current: usize,
    total: usize,
    file: []const u8,
) !void {
    const bar_width = 30;
    const filled = (current * bar_width) / total;
    const percent = (current * 100) / total;

    try stdout.writeAll("\r[");

    // Draw filled portion
    var i: usize = 0;
    while (i < filled) : (i += 1) {
        try stdout.writeAll("=");
    }

    // Draw arrow if not complete
    if (filled < bar_width) {
        try stdout.writeAll(">");
        i += 1;
    }

    // Draw empty portion
    while (i < bar_width) : (i += 1) {
        try stdout.writeAll(" ");
    }

    try stdout.print("] {d}% ({}/{}) {s}       ", .{percent, current, total, file});
    try stdout.flush();
}

fn downloadFile(allocator: std.mem.Allocator, url: []const u8, output_path: []const u8) !void {
    // Parse uri
    const uri = try std.Uri.parse(url);

    // Create client
    var client = std.http.Client{.allocator = allocator};
    defer client.deinit();

    //Setup buffers for writing and redirecting
    var writer_buffer: [8 * 1024]u8 = undefined;
    var redirect_buffer: [8 * 1024]u8 = undefined;

    //Open output and get writer
    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();

    var file_writer = file.writer(&writer_buffer);

    const result = try client.fetch(.{
        .location = .{.uri = uri}, 
        .method = .GET,
        .redirect_buffer = &redirect_buffer, 
        .response_writer = &file_writer.interface,
    });

    try file_writer.interface.flush();
    
    if(result.status != .ok) {
        return error.HTTPRequest;
    }
}
