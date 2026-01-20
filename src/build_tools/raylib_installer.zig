const std = @import("std");
const FileWriter = @import("FileWriter.zig").FileWriter;

const raylib_url = "https://github.com/raylib-zig/raylib-zig/archive/refs/heads/devel.tar.gz";

// Code to inject after "const optimize = b.standardOptimizeOption"
const raylib_dep_code =
    \\
    \\    // Raylib dependency
    \\    const raylib_dep = b.dependency("raylib_zig", .{
    \\        .target = target,
    \\        .optimize = optimize,
    \\    });
    \\    const raylib = raylib_dep.module("raylib");
    \\    const raylib_artifact = raylib_dep.artifact("raylib");
    \\
;

// Code to inject after Prescient import line
const raylib_import_code = "                .{ .name = \"raylib\", .module = raylib },\n";

// Code to inject before b.installArtifact(exe)
const raylib_link_code = "    exe.linkLibrary(raylib_artifact);\n";

// Patterns to search for
const optimize_pattern = "const optimize = b.standardOptimizeOption";
const prescient_import_pattern = ".{ .name = \"Prescient\", .module = mod }";
const install_artifact_pattern = "b.installArtifact(exe);";

// Check pattern for already installed
const already_installed_pattern = "raylib_dep";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var args = std.process.args();
    _ = args.next(); // skip program name

    const root_dir = args.next() orelse {
        try stdout.writeAll("Error: No root directory provided\n");
        try stdout.flush();
        return error.NoRootDir;
    };

    // Construct path to build.zig
    const build_zig_path = try std.fmt.allocPrint(allocator, "{s}/build.zig", .{root_dir});
    defer allocator.free(build_zig_path);

    try stdout.writeAll("Installing raylib-zig bindings...\n");
    try stdout.flush();

    // Read existing build.zig
    const build_zig_content = std.fs.cwd().readFileAlloc(allocator, build_zig_path, 1024 * 1024) catch |err| {
        try stdout.print("Error: Could not read build.zig: {}\n", .{err});
        try stdout.flush();
        return err;
    };
    defer allocator.free(build_zig_content);

    // Check if raylib is already installed
    if (std.mem.indexOf(u8, build_zig_content, already_installed_pattern) != null) {
        try stdout.writeAll("Raylib is already installed in this project.\n");
        try stdout.flush();
        return;
    }

    // Run zig fetch to download raylib-zig
    try stdout.writeAll("Fetching raylib-zig from GitHub...\n");
    try stdout.flush();

    var fetch_process = std.process.Child.init(&.{ "zig", "fetch", "--save", raylib_url }, allocator);
    fetch_process.cwd = root_dir;
    const fetch_result = fetch_process.spawnAndWait() catch |err| {
        try stdout.print("Error: Could not run zig fetch: {}\n", .{err});
        try stdout.flush();
        return err;
    };

    switch (fetch_result) {
        .Exited => |code| {
            if (code != 0) {
                try stdout.print("Error: zig fetch failed with exit code {d}\n", .{code});
                try stdout.flush();
                return error.FetchFailed;
            }
        },
        .Signal => |sig| {
            try stdout.print("Error: zig fetch terminated by signal {d}\n", .{sig});
            try stdout.flush();
            return error.FetchFailed;
        },
        .Stopped => |sig| {
            try stdout.print("Error: zig fetch stopped by signal {d}\n", .{sig});
            try stdout.flush();
            return error.FetchFailed;
        },
        .Unknown => |code| {
            try stdout.print("Error: zig fetch failed with unknown status {d}\n", .{code});
            try stdout.flush();
            return error.FetchFailed;
        },
    }

    try stdout.writeAll("Modifying build.zig...\n");
    try stdout.flush();

    // Process build.zig line by line and inject raylib code
    var file_writer = FileWriter{ .filePath = build_zig_path };
    defer file_writer.deinit(allocator);

    var lines = std.mem.splitScalar(u8, build_zig_content, '\n');
    var inject_count: u32 = 0;

    while (lines.next()) |line| {
        // Write the current line
        try file_writer.writeLine(allocator, line);

        // Check for injection points
        if (std.mem.indexOf(u8, line, optimize_pattern) != null) {
            try file_writer.write(allocator, raylib_dep_code);
            inject_count += 1;
        } else if (std.mem.indexOf(u8, line, prescient_import_pattern) != null) {
            try file_writer.write(allocator, raylib_import_code);
            inject_count += 1;
        } else if (std.mem.indexOf(u8, line, install_artifact_pattern) != null) {
            // For installArtifact, we need to insert BEFORE this line
            // So we need to undo writing this line, write the link code, then rewrite the line
            // Actually, let's handle this differently - we'll look ahead
        }
    }

    // The above approach has an issue with the installArtifact injection (needs to be before, not after)
    // Let me rewrite with a better approach

    file_writer.fileContent.clearRetainingCapacity();

    lines = std.mem.splitScalar(u8, build_zig_content, '\n');
    inject_count = 0;

    while (lines.next()) |line| {
        // Check if this is the installArtifact line - inject BEFORE it
        if (std.mem.indexOf(u8, line, install_artifact_pattern) != null) {
            try file_writer.write(allocator, raylib_link_code);
            inject_count += 1;
        }

        // Write the current line
        try file_writer.writeLine(allocator, line);

        // Check for injection points that need code AFTER
        if (std.mem.indexOf(u8, line, optimize_pattern) != null) {
            try file_writer.write(allocator, raylib_dep_code);
            inject_count += 1;
        } else if (std.mem.indexOf(u8, line, prescient_import_pattern) != null) {
            try file_writer.write(allocator, raylib_import_code);
            inject_count += 1;
        }
    }

    // Remove trailing newline if present (splitScalar adds empty string at end)
    const content = file_writer.getContent();
    if (content.len > 0 and content[content.len - 1] == '\n') {
        _ = file_writer.fileContent.pop();
    }

    if (inject_count < 3) {
        try stdout.print("Warning: Only {d}/3 injection points found. build.zig may have unexpected format.\n", .{inject_count});
        try stdout.flush();
    }

    try file_writer.saveFile();

    try stdout.writeAll("\n✓ Raylib-zig installed successfully!\n\n");
    try stdout.writeAll("To use raylib in your code, import it with:\n");
    try stdout.writeAll("  const raylib = @import(\"raylib\");\n\n");
    try stdout.flush();
}
