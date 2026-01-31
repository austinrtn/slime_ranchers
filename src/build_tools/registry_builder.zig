const std = @import("std");
const ArrayList = std.ArrayList;
const print = std.debug.print;
const FileWriter = @import("FileWriter.zig").FileWriter;

/// Registry builder for Prescient ECS
/// Scans component/system directories and generates registry files
/// Also creates PoolRegistry.zig template if it doesn't exist

const FileData = struct {
    typeName: []const u8,
    fileName: []const u8,
    content: ?[]const u8 = null, // Store content for system dependency validation
};

const FileStorage = struct {
    fileData: ArrayList(FileData) = .empty,
    fileWriter: FileWriter,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        for (self.fileData.items) |data| {
            allocator.free(data.typeName);
            allocator.free(data.fileName);
            if (data.content) |content| {
                allocator.free(content);
            }
        }
        self.fileData.deinit(allocator);
        self.fileWriter.deinit(allocator);
    }
};

// ============================================================================
// Cache Structures and Functions
// ============================================================================

const CACHE_VERSION: u32 = 1;
const CACHE_DIR = ".prescient-cache";
const CACHE_FILE = "registry_hashes.bin";

const CacheEntry = struct {
    directory_hash: [32]u8, // SHA256 of directory state
    file_count: u32,
    last_modified: i128, // Newest file mtime (nanoseconds)
};

const CacheFile = struct {
    version: u32 = CACHE_VERSION,
    components: CacheEntry,
    systems: CacheEntry,
    pools: CacheEntry,
    factories: CacheEntry,
};

/// Computes SHA256 hash of a directory's state.
/// For systems, includes enabled status in the hash.
fn computeDirectoryHash(allocator: std.mem.Allocator, dir_path: []const u8, is_systems: bool) ![32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});

    // Collect and sort file entries
    var file_entries: ArrayList(struct { name: []const u8, content: []const u8 }) = .empty;
    defer {
        for (file_entries.items) |entry| {
            allocator.free(entry.name);
            allocator.free(entry.content);
        }
        file_entries.deinit(allocator);
    }

    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            // Return zeroed hash for non-existent directory
            return [_]u8{0} ** 32;
        }
        return err;
    };
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
            const file = try dir.openFile(entry.name, .{});
            defer file.close();

            const content = try file.readToEndAlloc(allocator, 1024 * 1024);
            errdefer allocator.free(content);

            const name_copy = try allocator.dupe(u8, entry.name);
            errdefer allocator.free(name_copy);

            try file_entries.append(allocator, .{ .name = name_copy, .content = content });
        }
    }

    // Sort by filename for consistent ordering
    std.mem.sort(@TypeOf(file_entries.items[0]), file_entries.items, {}, struct {
        fn lessThan(_: void, a: @TypeOf(file_entries.items[0]), b: @TypeOf(file_entries.items[0])) bool {
            return std.mem.lessThan(u8, a.name, b.name);
        }
    }.lessThan);

    // Hash each file: filename + content (+ enabled status for systems)
    for (file_entries.items) |entry| {
        hasher.update(entry.name);
        hasher.update(entry.content);

        // For systems, also hash the enabled status
        if (is_systems) {
            const enabled = parseEnabledField(entry.content);
            if (enabled) |e| {
                hasher.update(if (e) "enabled:true" else "enabled:false");
            } else {
                hasher.update("enabled:missing");
            }
        }
    }

    return hasher.finalResult();
}

/// Gets the newest modification time from a directory
fn getNewestMtime(dir_path: []const u8) !i128 {
    var newest: i128 = 0;

    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return 0;
        return err;
    };
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
            const stat = try dir.statFile(entry.name);
            if (stat.mtime > newest) {
                newest = stat.mtime;
            }
        }
    }

    return newest;
}

/// Counts .zig files in a directory
fn countZigFiles(dir_path: []const u8) !u32 {
    var count: u32 = 0;

    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return 0;
        return err;
    };
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
            count += 1;
        }
    }

    return count;
}

/// Loads the cache file if it exists and is valid
fn loadCacheFile(allocator: std.mem.Allocator, project_dir: []const u8) !?CacheFile {
    const cache_path = try std.fs.path.join(allocator, &.{ project_dir, CACHE_DIR, CACHE_FILE });
    defer allocator.free(cache_path);

    const file = std.fs.cwd().openFile(cache_path, .{}) catch |err| {
        if (err == error.FileNotFound) return null;
        return err;
    };
    defer file.close();

    const bytes = file.readToEndAlloc(allocator, 1024) catch return null;
    defer allocator.free(bytes);

    if (bytes.len != @sizeOf(CacheFile)) return null;

    const cache = std.mem.bytesToValue(CacheFile, bytes[0..@sizeOf(CacheFile)]);

    // Check version
    if (cache.version != CACHE_VERSION) return null;

    return cache;
}

/// Saves the cache file
fn saveCacheFile(allocator: std.mem.Allocator, project_dir: []const u8, cache: CacheFile) !void {
    const cache_dir = try std.fs.path.join(allocator, &.{ project_dir, CACHE_DIR });
    defer allocator.free(cache_dir);

    std.fs.cwd().makePath(cache_dir) catch |err| {
        print("Warning: Could not create cache directory: {}\n", .{err});
        return;
    };

    const cache_path = try std.fs.path.join(allocator, &.{ project_dir, CACHE_DIR, CACHE_FILE });
    defer allocator.free(cache_path);

    const file = std.fs.cwd().createFile(cache_path, .{}) catch |err| {
        print("Warning: Could not create cache file: {}\n", .{err});
        return;
    };
    defer file.close();

    const bytes = std.mem.asBytes(&cache);
    file.writeAll(bytes) catch |err| {
        print("Warning: Could not write cache file: {}\n", .{err});
    };
}

/// Checks if a cache entry is still valid for a directory
fn isCacheValid(cache_entry: CacheEntry, current_hash: [32]u8, current_file_count: u32) bool {
    // Hash must match
    if (!std.mem.eql(u8, &cache_entry.directory_hash, &current_hash)) return false;

    // File count must match
    if (cache_entry.file_count != current_file_count) return false;

    return true;
}

/// Checks if the registry file exists
fn registryExists(allocator: std.mem.Allocator, project_dir: []const u8, registry_name: []const u8) !bool {
    const registry_path = try std.fs.path.join(allocator, &.{ project_dir, "src", "registries", registry_name });
    defer allocator.free(registry_path);

    std.fs.cwd().access(registry_path, .{}) catch return false;
    return true;
}

pub fn main() !void {
    print("\n=======================\n", .{});
    print("Building Registries....\n", .{});
    print("=======================\n\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();
    _ = args.next();

    const project_dir = args.next() orelse {
        print("Error: Project directory not provided.\n", .{});
        return error.MissingProjectDir;
    };

    // Ensure registries directory exists
    const registries_dir = try std.fs.path.join(allocator, &.{ project_dir, "src", "registries" });
    defer allocator.free(registries_dir);

    std.fs.cwd().makePath(registries_dir) catch |err| {
        print("Error creating registries directory: {}\n", .{err});
        return err;
    };
    print("Ensured registries directory exists: {s}\n\n", .{registries_dir});

    // Ensure Phases.zig exists (user-editable, not generated)
    try ensurePhasesFile(allocator, project_dir);

    // Load existing cache
    const cache = try loadCacheFile(allocator, project_dir);
    var new_cache: CacheFile = .{
        .version = CACHE_VERSION,
        .components = .{ .directory_hash = [_]u8{0} ** 32, .file_count = 0, .last_modified = @as(i128, 0) },
        .systems = .{ .directory_hash = [_]u8{0} ** 32, .file_count = 0, .last_modified = @as(i128, 0) },
        .pools = .{ .directory_hash = [_]u8{0} ** 32, .file_count = 0, .last_modified = @as(i128, 0) },
        .factories = .{ .directory_hash = [_]u8{0} ** 32, .file_count = 0, .last_modified = @as(i128, 0) },
    };

    // Track what was rebuilt
    var components_rebuilt = false;
    var systems_rebuilt = false;
    var pools_rebuilt = false;
    var factories_rebuilt = false;

    // Build ComponentRegistry.zig (with cache check)
    {
        const components_dir = try std.fs.path.join(allocator, &.{ project_dir, "src", "components" });
        defer allocator.free(components_dir);

        const comp_hash = try computeDirectoryHash(allocator, components_dir, false);
        const comp_count = try countZigFiles(components_dir);
        const comp_mtime = try getNewestMtime(components_dir);
        const registry_ok = try registryExists(allocator, project_dir, "ComponentRegistry.zig");

        new_cache.components = .{
            .directory_hash = comp_hash,
            .file_count = comp_count,
            .last_modified = comp_mtime,
        };

        if (cache != null and registry_ok and isCacheValid(cache.?.components, comp_hash, comp_count)) {
            print("Components unchanged, skipping...\n\n", .{});
        } else {
            try buildRegistry(allocator, project_dir, "components", "ComponentRegistry.zig", "Component");
            components_rebuilt = true;
            // Save cache immediately after successful build to prevent stale state on later failures
            try saveCacheFile(allocator, project_dir, new_cache);
        }
    }

    // Build SystemRegistry.zig (with cache check)
    {
        const systems_dir = try std.fs.path.join(allocator, &.{ project_dir, "src", "systems" });
        defer allocator.free(systems_dir);

        const sys_hash = try computeDirectoryHash(allocator, systems_dir, true);
        const sys_count = try countZigFiles(systems_dir);
        const sys_mtime = try getNewestMtime(systems_dir);
        const registry_ok = try registryExists(allocator, project_dir, "SystemRegistry.zig");
        const metadata_ok = try registryExists(allocator, project_dir, "SystemMetadata.zig");

        new_cache.systems = .{
            .directory_hash = sys_hash,
            .file_count = sys_count,
            .last_modified = sys_mtime,
        };

        if (cache != null and registry_ok and metadata_ok and isCacheValid(cache.?.systems, sys_hash, sys_count)) {
            print("Systems unchanged, skipping...\n\n", .{});
        } else {
            try buildRegistry(allocator, project_dir, "systems", "SystemRegistry.zig", "System");
            systems_rebuilt = true;
            try saveCacheFile(allocator, project_dir, new_cache);
        }
    }

    // Build PoolRegistry.zig (with cache check)
    // Note: Pools depend on ComponentRegistry, so rebuild if components changed
    {
        const pools_dir = try std.fs.path.join(allocator, &.{ project_dir, "src", "pools" });
        defer allocator.free(pools_dir);

        const pool_hash = try computeDirectoryHash(allocator, pools_dir, false);
        const pool_count = try countZigFiles(pools_dir);
        const pool_mtime = try getNewestMtime(pools_dir);
        const registry_ok = try registryExists(allocator, project_dir, "PoolRegistry.zig");

        new_cache.pools = .{
            .directory_hash = pool_hash,
            .file_count = pool_count,
            .last_modified = pool_mtime,
        };

        if (cache != null and registry_ok and !components_rebuilt and isCacheValid(cache.?.pools, pool_hash, pool_count)) {
            print("Pools unchanged, skipping...\n\n", .{});
        } else {
            try buildPoolRegistry(allocator, project_dir);
            pools_rebuilt = true;
            try saveCacheFile(allocator, project_dir, new_cache);
        }
    }

    // Build FactoryRegistry.zig (with cache check)
    // Note: Factories depend on PoolRegistry, so rebuild if pools changed
    {
        const factories_dir = try std.fs.path.join(allocator, &.{ project_dir, "src", "factories" });
        defer allocator.free(factories_dir);

        const factory_hash = try computeDirectoryHash(allocator, factories_dir, false);
        const factory_count = try countZigFiles(factories_dir);
        const factory_mtime = try getNewestMtime(factories_dir);
        const registry_ok = try registryExists(allocator, project_dir, "FactoryRegistry.zig");

        new_cache.factories = .{
            .directory_hash = factory_hash,
            .file_count = factory_count,
            .last_modified = factory_mtime,
        };

        if (cache != null and registry_ok and !pools_rebuilt and isCacheValid(cache.?.factories, factory_hash, factory_count)) {
            print("Factories unchanged, skipping...\n\n", .{});
        } else {
            try buildFactoryRegistry(allocator, project_dir);
            factories_rebuilt = true;
            try saveCacheFile(allocator, project_dir, new_cache);
        }
    }

    // Print summary
    const rebuilt_count = @as(u8, @intFromBool(components_rebuilt)) +
        @as(u8, @intFromBool(systems_rebuilt)) +
        @as(u8, @intFromBool(pools_rebuilt)) +
        @as(u8, @intFromBool(factories_rebuilt));

    print("\n=======================\n", .{});
    if (rebuilt_count == 0) {
        print("All registries up to date!\n", .{});
    } else {
        print("Rebuilt {} registr{s}!\n", .{ rebuilt_count, if (rebuilt_count == 1) "y" else "ies" });
    }
    print("=======================\n\n", .{});
}

fn buildRegistry(
    allocator: std.mem.Allocator,
    project_dir: []const u8,
    directoryName: []const u8,
    registryName: []const u8,
    varName: []const u8,
) !void {
    const directoryPath = try std.fs.path.join(allocator, &.{ project_dir, "src", directoryName });
    defer allocator.free(directoryPath);

    const registryPath = try std.fs.path.join(allocator, &.{ project_dir, "src", "registries", registryName });
    defer allocator.free(registryPath);

    var fileStorage = FileStorage{ .fileWriter = .{ .filePath = registryPath } };
    defer fileStorage.deinit(allocator);

    print("Scanning {s} directory: {s}\n", .{ varName, directoryPath });

    const is_system_registry = std.mem.eql(u8, varName, "System");
    const filesFound = getFileData(allocator, &fileStorage, directoryPath, is_system_registry) catch |err| {
        if (err == error.FileNotFound) {
            print("  Directory does not exist. Creating empty registry.\n", .{});
            try writeEmptyRegistry(allocator, &fileStorage, varName);
            try fileStorage.fileWriter.saveFile();
            // Also generate empty SystemMetadata.zig for systems
            if (is_system_registry) {
                try writeEmptySystemMetadata(allocator, project_dir);
            }
            return;
        }
        return err;
    };

    if (!filesFound) {
        print("  No .zig files found. Creating empty registry.\n", .{});
        try writeEmptyRegistry(allocator, &fileStorage, varName);
        try fileStorage.fileWriter.saveFile();
        // Also generate empty SystemMetadata.zig for systems
        if (is_system_registry) {
            try writeEmptySystemMetadata(allocator, project_dir);
        }
        return;
    }

    print("  Found {} files.\n", .{fileStorage.fileData.items.len});

    // Validate system dependencies (only for systems)
    if (std.mem.eql(u8, varName, "System")) {
        try validateSystemDependencies(allocator, &fileStorage, directoryPath);
    }

    try writeImports(allocator, &fileStorage, directoryName);

    // Generate TypeMap for Components and Systems
    if (std.mem.eql(u8, varName, "Component")) {
        try writeCompTypeMap(allocator, &fileStorage, directoryName);
    } else if (std.mem.eql(u8, varName, "System")) {
        try writeSystemTypeMap(allocator, &fileStorage, directoryName);
    }

    try writeDataStructures(allocator, &fileStorage, varName);

    try fileStorage.fileWriter.saveFile();
    print("  Generated: {s}\n", .{registryPath});

    // Generate SystemMetadata.zig for systems
    if (std.mem.eql(u8, varName, "System")) {
        try buildSystemMetadata(allocator, &fileStorage, project_dir, directoryPath);
    }
}

fn getFileData(allocator: std.mem.Allocator, fs: *FileStorage, directory: []const u8, is_system_registry: bool) !bool {
    var dir = std.fs.cwd().openDir(directory, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return err;
        return err;
    };
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
            const file = try dir.openFile(entry.name, .{});
            defer file.close();

            const content = try file.readToEndAlloc(allocator, 1024 * 1024);

            // Parse type name from file (struct, enum, union, or type alias)
            const typeName = parseTypeName(content) orelse {
                print("  Warning: No type definition found in {s}, skipping.\n", .{entry.name});
                allocator.free(content);
                continue;
            };

            // Check enabled field (required for systems)
            if (is_system_registry) {
                const enabled = parseEnabledField(content) orelse {
                    print("  ERROR: System {s} missing required 'pub const enabled: bool' field!\n", .{typeName});
                    return error.MissingEnabledField;
                };

                if (!enabled) {
                    print("  Skipping {s} (enabled = false)\n", .{typeName});
                    allocator.free(content);
                    continue;
                }
            }

            const fileData = FileData{
                .typeName = try allocator.dupe(u8, typeName),
                .fileName = try allocator.dupe(u8, entry.name),
                .content = content, // Store for validation
            };
            try fs.fileData.append(allocator, fileData);
        }
    }

    // Sort by type name for consistent ordering
    std.mem.sort(FileData, fs.fileData.items, {}, struct {
        fn lessThan(_: void, a: FileData, b: FileData) bool {
            return std.mem.lessThan(u8, a.typeName, b.typeName);
        }
    }.lessThan);

    return fs.fileData.items.len > 0;
}

fn validateSystemDependencies(allocator: std.mem.Allocator, fs: *FileStorage, directory: []const u8) !void {
    _ = fs; // Unused parameter
    // First, collect all systems (both enabled and disabled)
    var all_systems: ArrayList(FileData) = .empty;
    defer {
        for (all_systems.items) |data| {
            allocator.free(data.typeName);
            allocator.free(data.fileName);
            if (data.content) |content| {
                allocator.free(content);
            }
        }
        all_systems.deinit(allocator);
    }

    var dir = std.fs.cwd().openDir(directory, .{ .iterate = true }) catch return;
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
            const file = try dir.openFile(entry.name, .{});
            defer file.close();

            const content = try file.readToEndAlloc(allocator, 1024 * 1024);
            const typeName = parseTypeName(content) orelse {
                allocator.free(content);
                continue;
            };

            const fileData = FileData{
                .typeName = try allocator.dupe(u8, typeName),
                .fileName = try allocator.dupe(u8, entry.name),
                .content = content,
            };
            try all_systems.append(allocator, fileData);
        }
    }

    // Build a list of enabled system names
    var enabled_systems: ArrayList([]const u8) = .empty;
    defer enabled_systems.deinit(allocator);

    for (all_systems.items) |system| {
        if (system.content) |content| {
            if (!isSystemDisabled(content)) {
                try enabled_systems.append(allocator, system.typeName);
            }
        }
    }

    // Check each enabled system's dependencies
    for (all_systems.items) |system| {
        if (system.content) |content| {
            // Only check enabled systems
            if (isSystemDisabled(content)) continue;

            // Check runs_before and runs_after declarations
            const runs_before = parseDependencyDecl(allocator, content, "runs_before") catch null;
            defer if (runs_before) |deps| {
                for (deps) |dep| allocator.free(dep);
                allocator.free(deps);
            };

            const runs_after = parseDependencyDecl(allocator, content, "runs_after") catch null;
            defer if (runs_after) |deps| {
                for (deps) |dep| allocator.free(dep);
                allocator.free(deps);
            };

            if (runs_before) |deps| {
                for (deps) |dep_name| {
                    // Check if this dependency is in the enabled systems list
                    var found = false;
                    for (enabled_systems.items) |enabled| {
                        if (std.mem.eql(u8, dep_name, enabled)) {
                            found = true;
                            break;
                        }
                    }

                    if (!found) {
                        // Check if it's a disabled system
                        var is_disabled = false;
                        for (all_systems.items) |other| {
                            if (std.mem.eql(u8, dep_name, other.typeName)) {
                                if (other.content) |other_content| {
                                    if (isSystemDisabled(other_content)) {
                                        is_disabled = true;
                                        break;
                                    }
                                }
                            }
                        }

                        if (is_disabled) {
                            print("\n  ERROR: System '{s}' references disabled system '{s}' in runs_before.\n", .{ system.typeName, dep_name });
                            print("         Either enable '{s}' or remove it from '{s}' dependencies.\n\n", .{ dep_name, system.typeName });
                            return error.DisabledSystemReference;
                        }
                    }
                }
            }

            if (runs_after) |deps| {
                for (deps) |dep_name| {
                    var found = false;
                    for (enabled_systems.items) |enabled| {
                        if (std.mem.eql(u8, dep_name, enabled)) {
                            found = true;
                            break;
                        }
                    }

                    if (!found) {
                        var is_disabled = false;
                        for (all_systems.items) |other| {
                            if (std.mem.eql(u8, dep_name, other.typeName)) {
                                if (other.content) |other_content| {
                                    if (isSystemDisabled(other_content)) {
                                        is_disabled = true;
                                        break;
                                    }
                                }
                            }
                        }

                        if (is_disabled) {
                            print("\n  ERROR: System '{s}' references disabled system '{s}' in runs_after.\n", .{ system.typeName, dep_name });
                            print("         Either enable '{s}' or remove it from '{s}' dependencies.\n\n", .{ dep_name, system.typeName });
                            return error.DisabledSystemReference;
                        }
                    }
                }
            }
        }
    }
}

fn isSystemDisabled(content: []const u8) bool {
    var lines = std.mem.splitAny(u8, content, "\n");
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, "//")) continue;

        if (std.mem.indexOf(u8, line, "pub const enabled") != null) {
            if (std.mem.indexOf(u8, line, "false") != null) {
                return true;
            }
            return false;
        }
    }
    return false; // No enabled field means enabled by default
}

fn parseDependencyDecl(allocator: std.mem.Allocator, content: []const u8, decl_name: []const u8) ![][]const u8 {
    var deps: ArrayList([]const u8) = .empty;
    errdefer {
        for (deps.items) |dep| allocator.free(dep);
        deps.deinit(allocator);
    }

    // Look for "pub const runs_before = &.{" or "pub const runs_after = &.{"
    const search_str = try std.fmt.allocPrint(allocator, "pub const {s}", .{decl_name});
    defer allocator.free(search_str);

    const start_idx = std.mem.indexOf(u8, content, search_str) orelse return error.NotFound;
    const after_decl = content[start_idx + search_str.len ..];

    // Find the opening brace
    const open_brace = std.mem.indexOf(u8, after_decl, "{") orelse return error.NotFound;
    const close_brace = std.mem.indexOf(u8, after_decl[open_brace..], "}") orelse return error.NotFound;

    // Extract content between braces
    const deps_content = after_decl[open_brace + 1 .. open_brace + close_brace];

    // Parse dependency names (they look like .SystemName)
    var tokens = std.mem.tokenizeAny(u8, deps_content, " \t\r\n,");
    while (tokens.next()) |token| {
        if (std.mem.startsWith(u8, token, ".")) {
            const dep_name = std.mem.trim(u8, token[1..], " \t\r\n,}");
            if (dep_name.len > 0) {
                try deps.append(allocator, try allocator.dupe(u8, dep_name));
            }
        }
    }

    return deps.toOwnedSlice(allocator);
}

fn parseTypeName(content: []const u8) ?[]const u8 {
    var lines = std.mem.splitAny(u8, content, "\n");

    while (lines.next()) |line| {
        // Look for "pub const Name = struct/enum/union" or "pub const Name = SomeType;"
        var tokens = std.mem.tokenizeAny(u8, line, " \t\r\n");

        var token_index: usize = 0;
        var found_pub = false;
        var found_const = false;
        var name: ?[]const u8 = null;
        var found_equals = false;

        while (tokens.next()) |token| {
            if (token_index == 0 and std.mem.eql(u8, token, "pub")) {
                found_pub = true;
            } else if (token_index == 1 and found_pub and std.mem.eql(u8, token, "const")) {
                found_const = true;
            } else if (token_index == 2 and found_const) {
                name = token;
            } else if (token_index == 3 and name != null and std.mem.eql(u8, token, "=")) {
                found_equals = true;
            } else if (token_index == 4 and name != null and found_equals) {
                // Check for struct, enum, union (with or without trailing brace)
                if (std.mem.eql(u8, token, "struct") or std.mem.startsWith(u8, token, "struct{") or
                    std.mem.eql(u8, token, "enum") or std.mem.startsWith(u8, token, "enum{") or std.mem.startsWith(u8, token, "enum(") or
                    std.mem.eql(u8, token, "union") or std.mem.startsWith(u8, token, "union{") or std.mem.startsWith(u8, token, "union("))
                {
                    return name;
                }
                // Check for type alias (e.g., "pub const Color = u32;")
                // Token should end with semicolon or be a type name
                if (std.mem.endsWith(u8, token, ";") or isTypeName(token)) {
                    return name;
                }
            }
            token_index += 1;
        }
    }
    return null;
}

fn isTypeName(token: []const u8) bool {
    // Check for primitive types
    const primitives = [_][]const u8{
        "u8",    "u16",   "u32",   "u64",   "u128",  "usize",
        "i8",    "i16",   "i32",   "i64",   "i128",  "isize",
        "f16",   "f32",   "f64",   "f128",
        "bool",  "void",  "noreturn",
        "c_int", "c_uint", "c_long", "c_ulong",
    };

    for (primitives) |prim| {
        if (std.mem.eql(u8, token, prim)) return true;
    }

    // Check for slice, pointer, array, optional types
    if (token.len > 0) {
        const first = token[0];
        if (first == '[' or first == '*' or first == '?') return true;
    }

    // Check for user-defined types (starts with uppercase, or contains a dot for namespaced types)
    if (token.len > 0) {
        const first = token[0];
        if (first >= 'A' and first <= 'Z') return true;
        if (std.mem.indexOf(u8, token, ".") != null) return true;
    }

    return false;
}

/// Parses the 'enabled' field from a system file.
/// Returns true/false based on the value, or null if not found.
fn parseEnabledField(content: []const u8) ?bool {
    var lines = std.mem.splitAny(u8, content, "\n");

    while (lines.next()) |line| {
        // Look for "pub const enabled" pattern
        var tokens = std.mem.tokenizeAny(u8, line, " \t\r\n");

        var token_index: usize = 0;
        var found_pub = false;
        var found_const = false;
        var found_enabled = false;
        var found_equals = false;

        while (tokens.next()) |token| {
            if (token_index == 0 and std.mem.eql(u8, token, "pub")) {
                found_pub = true;
            } else if (token_index == 1 and found_pub and std.mem.eql(u8, token, "const")) {
                found_const = true;
            } else if (token_index == 2 and found_const and std.mem.eql(u8, token, "enabled")) {
                found_enabled = true;
            } else if (token_index == 2 and found_const and std.mem.eql(u8, token, "enabled:")) {
                // Handle "pub const enabled: bool = true;" format
                found_enabled = true;
                token_index += 1; // Skip the type check
            } else if (found_enabled and std.mem.eql(u8, token, "bool")) {
                // Skip type annotation
            } else if (found_enabled and std.mem.eql(u8, token, "=")) {
                found_equals = true;
            } else if (found_enabled and found_equals) {
                // Check for true/false value
                if (std.mem.eql(u8, token, "true") or std.mem.eql(u8, token, "true;")) {
                    return true;
                } else if (std.mem.eql(u8, token, "false") or std.mem.eql(u8, token, "false;")) {
                    return false;
                }
            }
            token_index += 1;
        }
    }
    return null;
}

fn writeEmptyRegistry(allocator: std.mem.Allocator, fs: *FileStorage, varName: []const u8) !void {
    try fs.fileWriter.writeLine(allocator, "const std = @import(\"std\");");
    try fs.fileWriter.writeLine(allocator, "");
    try fs.fileWriter.writeFmt(allocator, "// Generated by: zig build registry\n", .{});
    try fs.fileWriter.writeFmt(allocator, "// Add {s}s to src/{s}s/ and rebuild\n", .{ varName, varName });
    try fs.fileWriter.writeLine(allocator, "");

    // Generate TypeMap for Components and Systems
    if (std.mem.eql(u8, varName, "Component")) {
        try fs.fileWriter.writeLine(allocator, "pub const CompTypeMap = struct {};");
        try fs.fileWriter.writeLine(allocator, "");
    } else if (std.mem.eql(u8, varName, "System")) {
        try fs.fileWriter.writeLine(allocator, "pub const SystemTypeMap = struct {};");
        try fs.fileWriter.writeLine(allocator, "");
    }

    try fs.fileWriter.writeFmt(allocator, "pub const {s}Name = enum {{\n", .{varName});
    try fs.fileWriter.writeLine(allocator, "");
    try fs.fileWriter.writeLine(allocator, "};");
    try fs.fileWriter.writeLine(allocator, "");
    try fs.fileWriter.writeFmt(allocator, "pub const {s}Types = [_]type {{\n", .{varName});
    try fs.fileWriter.writeLine(allocator, "");
    try fs.fileWriter.writeLine(allocator, "};");
    try fs.fileWriter.writeLine(allocator, "");

    // Build the lowercase version properly
    var lowercase_first: [1]u8 = undefined;
    _ = std.ascii.lowerString(&lowercase_first, varName[0..1]);
    try fs.fileWriter.writeFmt(allocator, "pub fn getTypeByName(comptime {c}{s}_name: {s}Name) type {{\n", .{ lowercase_first[0], varName[1..], varName });
    try fs.fileWriter.writeFmt(allocator, "    const index = @intFromEnum({c}{s}_name);\n", .{ lowercase_first[0], varName[1..] });
    try fs.fileWriter.writeFmt(allocator, "    return {s}Types[index];\n", .{varName});
    try fs.fileWriter.writeLine(allocator, "}");
}

fn writeImports(allocator: std.mem.Allocator, fs: *FileStorage, directoryName: []const u8) !void {
    try fs.fileWriter.writeLine(allocator, "const std = @import(\"std\");");
    try fs.fileWriter.writeLine(allocator, "");

    for (fs.fileData.items) |data| {
        try fs.fileWriter.writeFmt(
            allocator,
            "pub const {s} = @import(\"../{s}/{s}\").{s};\n",
            .{ data.typeName, directoryName, data.fileName, data.typeName },
        );
    }
    try fs.fileWriter.writeLine(allocator, "");
}

fn writeCompTypeMap(allocator: std.mem.Allocator, fs: *FileStorage, directoryName: []const u8) !void {
    try fs.fileWriter.writeLine(allocator, "pub const CompTypeMap = struct {");
    for (fs.fileData.items) |data| {
        try fs.fileWriter.writeFmt(
            allocator,
            "    pub const {s} = @import(\"../{s}/{s}\").{s};\n",
            .{ data.typeName, directoryName, data.fileName, data.typeName },
        );
    }
    try fs.fileWriter.writeLine(allocator, "};");
    try fs.fileWriter.writeLine(allocator, "");
}

fn writeSystemTypeMap(allocator: std.mem.Allocator, fs: *FileStorage, directoryName: []const u8) !void {
    try fs.fileWriter.writeLine(allocator, "pub const SystemTypeMap = struct {");
    for (fs.fileData.items) |data| {
        try fs.fileWriter.writeFmt(
            allocator,
            "    pub const {s} = @import(\"../{s}/{s}\").{s};\n",
            .{ data.typeName, directoryName, data.fileName, data.typeName },
        );
    }
    try fs.fileWriter.writeLine(allocator, "};");
    try fs.fileWriter.writeLine(allocator, "");
}

fn writeDataStructures(allocator: std.mem.Allocator, fs: *FileStorage, varName: []const u8) !void {
    // Write enum
    try fs.fileWriter.writeFmt(allocator, "pub const {s}Name = enum {{\n", .{varName});
    for (fs.fileData.items) |data| {
        try fs.fileWriter.writeFmt(allocator, "    {s},\n", .{data.typeName});
    }
    try fs.fileWriter.writeLine(allocator, "};");
    try fs.fileWriter.writeLine(allocator, "");

    // Write types array
    try fs.fileWriter.writeFmt(allocator, "pub const {s}Types = [_]type {{\n", .{varName});
    for (fs.fileData.items) |data| {
        try fs.fileWriter.writeFmt(allocator, "    {s},\n", .{data.typeName});
    }
    try fs.fileWriter.writeLine(allocator, "};");
    try fs.fileWriter.writeLine(allocator, "");

    // Write getTypeByName function
    var lowercase_first: [1]u8 = undefined;
    _ = std.ascii.lowerString(&lowercase_first, varName[0..1]);
    try fs.fileWriter.writeFmt(allocator, "pub fn getTypeByName(comptime {c}{s}_name: {s}Name) type {{\n", .{ lowercase_first[0], varName[1..], varName });
    try fs.fileWriter.writeFmt(allocator, "    const index = @intFromEnum({c}{s}_name);\n", .{ lowercase_first[0], varName[1..] });
    try fs.fileWriter.writeFmt(allocator, "    return {s}Types[index];\n", .{varName});
    try fs.fileWriter.writeLine(allocator, "}");
}

fn buildPoolRegistry(allocator: std.mem.Allocator, project_dir: []const u8) !void {
    const poolsDir = try std.fs.path.join(allocator, &.{ project_dir, "src", "pools" });
    defer allocator.free(poolsDir);

    const registryPath = try std.fs.path.join(allocator, &.{ project_dir, "src", "registries", "PoolRegistry.zig" });
    defer allocator.free(registryPath);

    var fileStorage = FileStorage{ .fileWriter = .{ .filePath = registryPath } };
    defer fileStorage.deinit(allocator);

    print("Scanning Pool directory: {s}\n", .{poolsDir});

    const filesFound = getFileData(allocator, &fileStorage, poolsDir, false) catch |err| {
        if (err == error.FileNotFound) {
            print("  Directory does not exist. Creating empty PoolRegistry.\n", .{});
            try writeEmptyPoolRegistry(allocator, &fileStorage);
            try fileStorage.fileWriter.saveFile();
            return;
        }
        return err;
    };

    if (!filesFound) {
        print("  No .zig files found. Creating empty PoolRegistry.\n", .{});
        try writeEmptyPoolRegistry(allocator, &fileStorage);
        try fileStorage.fileWriter.saveFile();
        return;
    }

    print("  Found {} pool files.\n", .{fileStorage.fileData.items.len});

    try writePoolRegistryHeader(allocator, &fileStorage);
    try writePoolNameEnum(allocator, &fileStorage);
    try writePoolImports(allocator, &fileStorage);
    try writePoolTypeMap(allocator, &fileStorage);
    try writePoolDataStructures(allocator, &fileStorage);
    try writePoolStaticFunctions(allocator, &fileStorage);

    try fileStorage.fileWriter.saveFile();
    print("  Generated: {s}\n", .{registryPath});
}

fn writeEmptyPoolRegistry(allocator: std.mem.Allocator, fs: *FileStorage) !void {
    try fs.fileWriter.writeLine(allocator, "const std = @import(\"std\");");
    try fs.fileWriter.writeLine(allocator, "const cr = @import(\"ComponentRegistry.zig\");");
    try fs.fileWriter.writeLine(allocator, "const EntityPool = @import(\"../ecs/EntityPool.zig\").EntityPool;");
    try fs.fileWriter.writeLine(allocator, "const StorageStrategy = @import(\"../ecs/StorageStrategy.zig\").StorageStrategy;");
    try fs.fileWriter.writeLine(allocator, "");
    try fs.fileWriter.writeLine(allocator, "// Generated by: zig build registry");
    try fs.fileWriter.writeLine(allocator, "// Add Pools to src/pools/ and rebuild");
    try fs.fileWriter.writeLine(allocator, "");
    try fs.fileWriter.writeLine(allocator, "pub const PoolName = enum(u32) {");
    try fs.fileWriter.writeLine(allocator, "");
    try fs.fileWriter.writeLine(allocator, "};");
    try fs.fileWriter.writeLine(allocator, "");
    try fs.fileWriter.writeLine(allocator, "pub const PoolTypeMap = struct {};");
    try fs.fileWriter.writeLine(allocator, "");
    try fs.fileWriter.writeLine(allocator, "pub const pool_types = [_]type{");
    try fs.fileWriter.writeLine(allocator, "");
    try fs.fileWriter.writeLine(allocator, "};");
    try fs.fileWriter.writeLine(allocator, "");
    try writePoolStaticFunctions(allocator, fs);
}

fn writePoolRegistryHeader(allocator: std.mem.Allocator, fs: *FileStorage) !void {
    try fs.fileWriter.writeLine(allocator, "const std = @import(\"std\");");
    try fs.fileWriter.writeLine(allocator, "const cr = @import(\"ComponentRegistry.zig\");");
    try fs.fileWriter.writeLine(allocator, "const EntityPool = @import(\"../ecs/EntityPool.zig\").EntityPool;");
    try fs.fileWriter.writeLine(allocator, "const StorageStrategy = @import(\"../ecs/StorageStrategy.zig\").StorageStrategy;");
    try fs.fileWriter.writeLine(allocator, "");
}

fn writePoolNameEnum(allocator: std.mem.Allocator, fs: *FileStorage) !void {
    // PoolName enum MUST come before pool imports to handle circular dependencies
    try fs.fileWriter.writeLine(allocator, "pub const PoolName = enum(u32) {");
    for (fs.fileData.items) |data| {
        try fs.fileWriter.writeFmt(allocator, "    {s},\n", .{data.typeName});
    }
    try fs.fileWriter.writeLine(allocator, "};");
    try fs.fileWriter.writeLine(allocator, "");
}

fn writePoolImports(allocator: std.mem.Allocator, fs: *FileStorage) !void {
    for (fs.fileData.items) |data| {
        try fs.fileWriter.writeFmt(
            allocator,
            "pub const {s} = @import(\"../pools/{s}\").{s};\n",
            .{ data.typeName, data.fileName, data.typeName },
        );
    }
    try fs.fileWriter.writeLine(allocator, "");
}

fn writePoolTypeMap(allocator: std.mem.Allocator, fs: *FileStorage) !void {
    try fs.fileWriter.writeLine(allocator, "pub const PoolTypeMap = struct {");
    for (fs.fileData.items) |data| {
        try fs.fileWriter.writeFmt(
            allocator,
            "    pub const {s} = @import(\"../pools/{s}\").{s};\n",
            .{ data.typeName, data.fileName, data.typeName },
        );
    }
    try fs.fileWriter.writeLine(allocator, "};");
    try fs.fileWriter.writeLine(allocator, "");
}

fn writePoolDataStructures(allocator: std.mem.Allocator, fs: *FileStorage) !void {
    // Write pool_types array
    try fs.fileWriter.writeLine(allocator, "pub const pool_types = [_]type{");
    for (fs.fileData.items) |data| {
        try fs.fileWriter.writeFmt(allocator, "    {s},\n", .{data.typeName});
    }
    try fs.fileWriter.writeLine(allocator, "};");
    try fs.fileWriter.writeLine(allocator, "");
}

fn writePoolStaticFunctions(allocator: std.mem.Allocator, fs: *FileStorage) !void {
    const static_functions =
        \\pub fn getPoolFromName(comptime pool: PoolName) type {
        \\    return pool_types[@intFromEnum(pool)];
        \\}
        \\
        \\/// Check at compile time if a pool contains a specific component
        \\pub fn poolHasComponent(comptime pool_name: PoolName, comptime component: cr.ComponentName) bool {
        \\    const PoolType = getPoolFromName(pool_name);
        \\    const pool_components = PoolType.COMPONENTS;
        \\
        \\    for (pool_components) |comp| {
        \\        if (comp == component) {
        \\            return true;
        \\        }
        \\    }
        \\    return false;
        \\}
        \\
        \\pub const PoolConfig = struct {
        \\    name: PoolName,
        \\    req: ?[]const cr.ComponentName = null,
        \\    components: ?[]const cr.ComponentName = null,
        \\    storage_strategy: StorageStrategy,
        \\};
        \\
    ;
    try fs.fileWriter.write(allocator, static_functions);
}

fn buildFactoryRegistry(allocator: std.mem.Allocator, project_dir: []const u8) !void {
    const factoriesDir = try std.fs.path.join(allocator, &.{ project_dir, "src", "factories" });
    defer allocator.free(factoriesDir);

    const registryPath = try std.fs.path.join(allocator, &.{ project_dir, "src", "registries", "FactoryRegistry.zig" });
    defer allocator.free(registryPath);

    var fileStorage = FileStorage{ .fileWriter = .{ .filePath = registryPath } };
    defer fileStorage.deinit(allocator);

    print("Scanning Factory directory: {s}\n", .{factoriesDir});

    const filesFound = getFileData(allocator, &fileStorage, factoriesDir, false) catch |err| {
        if (err == error.FileNotFound) {
            print("  Directory does not exist. Creating empty FactoryRegistry.\n", .{});
            try writeEmptyFactoryRegistry(allocator, &fileStorage);
            try fileStorage.fileWriter.saveFile();
            return;
        }
        return err;
    };

    if (!filesFound) {
        print("  No .zig files found. Creating empty FactoryRegistry.\n", .{});
        try writeEmptyFactoryRegistry(allocator, &fileStorage);
        try fileStorage.fileWriter.saveFile();
        return;
    }

    print("  Found {} factory files.\n", .{fileStorage.fileData.items.len});

    try writeFactoryRegistryHeader(allocator, &fileStorage);
    try writeFactoryNameEnum(allocator, &fileStorage);
    try writeFactoryImports(allocator, &fileStorage);
    try writeFactoryTypes(allocator, &fileStorage);
    try writeFactoryDataStructures(allocator, &fileStorage);
    try writeFactoryStaticFunctions(allocator, &fileStorage);

    try fileStorage.fileWriter.saveFile();
    print("  Generated: {s}\n", .{registryPath});
}

fn writeEmptyFactoryRegistry(allocator: std.mem.Allocator, fs: *FileStorage) !void {
    try fs.fileWriter.writeLine(allocator, "const std = @import(\"std\");");
    try fs.fileWriter.writeLine(allocator, "const pr = @import(\"PoolRegistry.zig\");");
    try fs.fileWriter.writeLine(allocator, "");
    try fs.fileWriter.writeLine(allocator, "// Generated by: zig build registry");
    try fs.fileWriter.writeLine(allocator, "// Add Factories to src/factories/ and rebuild");
    try fs.fileWriter.writeLine(allocator, "");
    try fs.fileWriter.writeLine(allocator, "pub const FactoryName = enum(u32) {");
    try fs.fileWriter.writeLine(allocator, "");
    try fs.fileWriter.writeLine(allocator, "};");
    try fs.fileWriter.writeLine(allocator, "");
    try fs.fileWriter.writeLine(allocator, "pub const factoryTypes = struct {};");
    try fs.fileWriter.writeLine(allocator, "");
    try fs.fileWriter.writeLine(allocator, "pub const factory_types = [_]type{");
    try fs.fileWriter.writeLine(allocator, "");
    try fs.fileWriter.writeLine(allocator, "};");
    try fs.fileWriter.writeLine(allocator, "");
    try writeFactoryStaticFunctions(allocator, fs);
}

fn writeFactoryRegistryHeader(allocator: std.mem.Allocator, fs: *FileStorage) !void {
    try fs.fileWriter.writeLine(allocator, "const std = @import(\"std\");");
    try fs.fileWriter.writeLine(allocator, "const pr = @import(\"PoolRegistry.zig\");");
    try fs.fileWriter.writeLine(allocator, "");
}

fn writeFactoryNameEnum(allocator: std.mem.Allocator, fs: *FileStorage) !void {
    try fs.fileWriter.writeLine(allocator, "pub const FactoryName = enum(u32) {");
    for (fs.fileData.items) |data| {
        try fs.fileWriter.writeFmt(allocator, "    {s},\n", .{data.typeName});
    }
    try fs.fileWriter.writeLine(allocator, "};");
    try fs.fileWriter.writeLine(allocator, "");
}

fn writeFactoryImports(allocator: std.mem.Allocator, fs: *FileStorage) !void {
    for (fs.fileData.items) |data| {
        try fs.fileWriter.writeFmt(
            allocator,
            "pub const {s} = @import(\"../factories/{s}\").{s};\n",
            .{ data.typeName, data.fileName, data.typeName },
        );
    }
    try fs.fileWriter.writeLine(allocator, "");
}

fn writeFactoryTypes(allocator: std.mem.Allocator, fs: *FileStorage) !void {
    try fs.fileWriter.writeLine(allocator, "pub const factoryTypes = struct {");
    for (fs.fileData.items) |data| {
        try fs.fileWriter.writeFmt(
            allocator,
            "    pub const {s} = @import(\"../factories/{s}\").{s};\n",
            .{ data.typeName, data.fileName, data.typeName },
        );
    }
    try fs.fileWriter.writeLine(allocator, "};");
    try fs.fileWriter.writeLine(allocator, "");
}

fn writeFactoryDataStructures(allocator: std.mem.Allocator, fs: *FileStorage) !void {
    try fs.fileWriter.writeLine(allocator, "pub const factory_types = [_]type{");
    for (fs.fileData.items) |data| {
        try fs.fileWriter.writeFmt(allocator, "    {s},\n", .{data.typeName});
    }
    try fs.fileWriter.writeLine(allocator, "};");
    try fs.fileWriter.writeLine(allocator, "");
}

fn writeFactoryStaticFunctions(allocator: std.mem.Allocator, fs: *FileStorage) !void {
    const static_functions =
        \\pub fn getFactoryFromName(comptime factory: FactoryName) type {
        \\    return factory_types[@intFromEnum(factory)];
        \\}
        \\
    ;
    try fs.fileWriter.write(allocator, static_functions);
}

// ============================================================================
// System Metadata Generation (for system_graph build tool)
// ============================================================================

const SystemMetadataInfo = struct {
    name: []const u8,
    phase: []const u8,
    reads: ArrayList([]const u8),
    writes: ArrayList([]const u8),
    runs_before: ArrayList([]const u8),
    runs_after: ArrayList([]const u8),
    has_queries: bool,

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        for (self.reads.items) |item| allocator.free(item);
        self.reads.deinit(allocator);
        for (self.writes.items) |item| allocator.free(item);
        self.writes.deinit(allocator);
        for (self.runs_before.items) |item| allocator.free(item);
        self.runs_before.deinit(allocator);
        for (self.runs_after.items) |item| allocator.free(item);
        self.runs_after.deinit(allocator);
    }
};

/// Parse component names from indirect_reads/indirect_writes declarations
fn parseIndirectComponents(allocator: std.mem.Allocator, content: []const u8, decl_name: []const u8) !ArrayList([]const u8) {
    var result: ArrayList([]const u8) = .empty;
    errdefer {
        for (result.items) |item| allocator.free(item);
        result.deinit(allocator);
    }

    const search_str = try std.fmt.allocPrint(allocator, "pub const {s}", .{decl_name});
    defer allocator.free(search_str);

    const start_idx = std.mem.indexOf(u8, content, search_str) orelse return result;
    const after_decl = content[start_idx + search_str.len ..];

    const open_brace = std.mem.indexOf(u8, after_decl, "{") orelse return result;
    const close_brace = std.mem.indexOf(u8, after_decl[open_brace..], "}") orelse return result;

    const components_content = after_decl[open_brace + 1 .. open_brace + close_brace];

    var tokens = std.mem.tokenizeAny(u8, components_content, " \t\r\n,");
    while (tokens.next()) |token| {
        if (std.mem.startsWith(u8, token, ".")) {
            const comp_name = std.mem.trim(u8, token[1..], " \t\r\n,}");
            if (comp_name.len > 0) {
                try result.append(allocator, try allocator.dupe(u8, comp_name));
            }
        }
    }

    return result;
}

/// Parse phase declaration from system file
/// Returns the phase name as a string, or error if not found
fn parsePhaseDecl(content: []const u8) ![]const u8 {
    // Look for "pub const phase" pattern
    const search_str = "pub const phase";
    const start_idx = std.mem.indexOf(u8, content, search_str) orelse return error.MissingPhase;
    const after_decl = content[start_idx + search_str.len ..];

    // Find the = sign
    const eq_idx = std.mem.indexOf(u8, after_decl, "=") orelse return error.MissingPhase;
    const after_eq = after_decl[eq_idx + 1 ..];

    // Find the phase value - looking for .PhaseName pattern
    const trimmed = std.mem.trim(u8, after_eq, " \t\r\n");
    if (!std.mem.startsWith(u8, trimmed, ".")) return error.MissingPhase;

    // Extract phase name until semicolon or whitespace
    var end: usize = 1;
    while (end < trimmed.len and trimmed[end] != ';' and trimmed[end] != ' ' and trimmed[end] != '\n' and trimmed[end] != '\r') {
        end += 1;
    }

    const phase_name = trimmed[1..end];
    if (phase_name.len == 0) return error.MissingPhase;

    return phase_name;
}

/// Parse query declarations from system files
fn parseQueryComponents(allocator: std.mem.Allocator, content: []const u8) !struct { reads: ArrayList([]const u8), writes: ArrayList([]const u8) } {
    var reads: ArrayList([]const u8) = .empty;
    var writes: ArrayList([]const u8) = .empty;
    errdefer {
        for (reads.items) |item| allocator.free(item);
        reads.deinit(allocator);
        for (writes.items) |item| allocator.free(item);
        writes.deinit(allocator);
    }

    // Look for both "pub const queries = struct {" and "queries: struct {"
    const queries_start = std.mem.indexOf(u8, content, "queries") orelse return .{ .reads = reads, .writes = writes };
    const after_queries = content[queries_start..];

    // Find the struct block
    const struct_idx = std.mem.indexOf(u8, after_queries, "struct {") orelse return .{ .reads = reads, .writes = writes };
    var brace_count: i32 = 1;
    var idx = struct_idx + "struct {".len;

    // Find the matching closing brace
    while (idx < after_queries.len and brace_count > 0) : (idx += 1) {
        if (after_queries[idx] == '{') brace_count += 1;
        if (after_queries[idx] == '}') brace_count -= 1;
    }

    if (brace_count != 0) return .{ .reads = reads, .writes = writes };

    const queries_block = after_queries[struct_idx + "struct {".len .. idx - 1];

    // Look for both QueryType(.{ and Query(.{ patterns
    var search_idx: usize = 0;

    // Try both patterns
    while (true) {
        const query_type_pos = std.mem.indexOfPos(u8, queries_block, search_idx, "QueryType(.{");
        const query_pos = std.mem.indexOfPos(u8, queries_block, search_idx, "Query(.{");

        const query_start = blk: {
            if (query_type_pos) |qtp| {
                if (query_pos) |qp| {
                    break :blk if (qtp < qp) qtp else qp;
                } else {
                    break :blk qtp;
                }
            } else if (query_pos) |qp| {
                break :blk qp;
            } else {
                break; // No more queries found
            }
        };

        // Determine which pattern was found and set the correct offset
        const is_query_type = if (query_start + "QueryType(.{".len <= queries_block.len)
            std.mem.eql(u8, queries_block[query_start .. query_start + "QueryType(.{".len], "QueryType(.{")
        else
            false;
        const query_content_start = if (is_query_type)
            query_start + "QueryType(.{".len
        else
            query_start + "Query(.{".len;

        // Find the closing })
        var paren_count: i32 = 1;
        var query_idx = query_content_start;
        while (query_idx < queries_block.len and paren_count > 0) : (query_idx += 1) {
            if (queries_block[query_idx] == '(' or queries_block[query_idx] == '{') paren_count += 1;
            if (queries_block[query_idx] == ')' or queries_block[query_idx] == '}') paren_count -= 1;
        }

        const query_config = queries_block[query_content_start..query_idx];

        // Parse .required/.optional (new format) and .read/.write (old format)
        // Look for patterns like ".read = &.{...}" or ".required = &.{...}"

        // Parse .required (reads AND writes required components)
        if (std.mem.indexOf(u8, query_config, ".required")) |_| {
            const components = try parseComponentsFromConfig(allocator, query_config, ".required");
            defer {
                for (components) |comp| allocator.free(comp);
                allocator.free(components);
            }
            for (components) |comp| {
                try reads.append(allocator, try allocator.dupe(u8, comp));
                try writes.append(allocator, try allocator.dupe(u8, comp));
            }
        }

        // Parse .optional (reads optional components)
        if (std.mem.indexOf(u8, query_config, ".optional")) |_| {
            const components = try parseComponentsFromConfig(allocator, query_config, ".optional");
            defer {
                for (components) |comp| allocator.free(comp);
                allocator.free(components);
            }
            for (components) |comp| {
                try reads.append(allocator, try allocator.dupe(u8, comp));
            }
        }

        // Parse .read (reads components)
        if (std.mem.indexOf(u8, query_config, ".read")) |_| {
            const components = try parseComponentsFromConfig(allocator, query_config, ".read");
            defer {
                for (components) |comp| allocator.free(comp);
                allocator.free(components);
            }
            for (components) |comp| {
                try reads.append(allocator, try allocator.dupe(u8, comp));
            }
        }

        // Parse .write (writes components)
        if (std.mem.indexOf(u8, query_config, ".write")) |_| {
            const components = try parseComponentsFromConfig(allocator, query_config, ".write");
            defer {
                for (components) |comp| allocator.free(comp);
                allocator.free(components);
            }
            for (components) |comp| {
                try writes.append(allocator, try allocator.dupe(u8, comp));
            }
        }

        search_idx = query_idx;
    }

    return .{ .reads = reads, .writes = writes };
}

/// Parse components from a query config string
/// Looks for pattern like ".keyword = &.{.Component1, .Component2}"
fn parseComponentsFromConfig(allocator: std.mem.Allocator, config: []const u8, keyword: []const u8) ![][]const u8 {
    var result: ArrayList([]const u8) = .empty;
    errdefer {
        for (result.items) |item| allocator.free(item);
        result.deinit(allocator);
    }

    // Find the keyword (e.g., ".read")
    const keyword_idx = std.mem.indexOf(u8, config, keyword) orelse return result.toOwnedSlice(allocator);
    const after_keyword = config[keyword_idx + keyword.len ..];

    // Find the &.{...} part after the keyword
    const amp_idx = std.mem.indexOf(u8, after_keyword, "&.{") orelse return result.toOwnedSlice(allocator);
    const start = amp_idx + "&.{".len;

    // Find the matching closing brace
    const end = std.mem.indexOfPos(u8, after_keyword, start, "}") orelse return result.toOwnedSlice(allocator);

    const components_str = after_keyword[start..end];
    var tokens = std.mem.tokenizeAny(u8, components_str, " \t\r\n,");

    while (tokens.next()) |token| {
        if (std.mem.startsWith(u8, token, ".")) {
            const comp_name = std.mem.trim(u8, token[1..], " \t\r\n,}");
            if (comp_name.len > 0) {
                try result.append(allocator, try allocator.dupe(u8, comp_name));
            }
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Build system metadata by parsing system files as text
fn buildSystemMetadata(allocator: std.mem.Allocator, fs: *FileStorage, project_dir: []const u8, systems_dir: []const u8) !void {
    _ = systems_dir;

    print("Generating SystemMetadata.zig...\n", .{});

    var metadata_list: ArrayList(SystemMetadataInfo) = .empty;
    defer {
        for (metadata_list.items) |*meta| {
            meta.deinit(allocator);
        }
        metadata_list.deinit(allocator);
    }

    // Parse each system file
    for (fs.fileData.items) |file_data| {
        const content = file_data.content orelse continue;

        // Parse queries
        const query_components = try parseQueryComponents(allocator, content);
        var reads = query_components.reads;
        var writes = query_components.writes;
        errdefer {
            for (reads.items) |item| allocator.free(item);
            reads.deinit(allocator);
            for (writes.items) |item| allocator.free(item);
            writes.deinit(allocator);
        }

        // Parse indirect reads/writes
        var indirect_reads = try parseIndirectComponents(allocator, content, "indirect_reads");
        var indirect_writes = try parseIndirectComponents(allocator, content, "indirect_writes");

        // Combine query components with indirect components
        for (indirect_reads.items) |comp| {
            try reads.append(allocator, try allocator.dupe(u8, comp));
        }
        for (indirect_writes.items) |comp| {
            try writes.append(allocator, try allocator.dupe(u8, comp));
        }

        indirect_reads.deinit(allocator);
        indirect_writes.deinit(allocator);

        // Parse phase declaration (required)
        const phase = parsePhaseDecl(content) catch {
            print("\n  ERROR: System '{s}' is missing required 'pub const phase: Phase = .XXX;' declaration!\n", .{file_data.typeName});
            print("         Add a phase declaration (e.g., 'pub const phase: Phase = .Update;')\n\n", .{});
            return error.MissingPhaseDeclaration;
        };

        // Parse runs_before/runs_after
        const runs_before = parseDependencyDecl(allocator, content, "runs_before") catch blk: {
            var empty: ArrayList([]const u8) = .empty;
            break :blk try empty.toOwnedSlice(allocator);
        };
        const runs_after = parseDependencyDecl(allocator, content, "runs_after") catch blk: {
            var empty: ArrayList([]const u8) = .empty;
            break :blk try empty.toOwnedSlice(allocator);
        };

        var runs_before_list: ArrayList([]const u8) = .empty;
        errdefer {
            for (runs_before_list.items) |item| allocator.free(item);
            runs_before_list.deinit(allocator);
        }
        for (runs_before) |dep| {
            try runs_before_list.append(allocator, try allocator.dupe(u8, dep));
        }
        for (runs_before) |dep| allocator.free(dep);
        allocator.free(runs_before);

        var runs_after_list: ArrayList([]const u8) = .empty;
        errdefer {
            for (runs_after_list.items) |item| allocator.free(item);
            runs_after_list.deinit(allocator);
        }
        for (runs_after) |dep| {
            try runs_after_list.append(allocator, try allocator.dupe(u8, dep));
        }
        for (runs_after) |dep| allocator.free(dep);
        allocator.free(runs_after);

        const has_queries = reads.items.len > 0 or writes.items.len > 0;

        try metadata_list.append(allocator, .{
            .name = file_data.typeName,
            .phase = phase,
            .reads = reads,
            .writes = writes,
            .runs_before = runs_before_list,
            .runs_after = runs_after_list,
            .has_queries = has_queries,
        });
    }

    // Deduplicate component lists
    for (metadata_list.items) |*meta| {
        try deduplicateComponents(allocator, &meta.reads);
        try deduplicateComponents(allocator, &meta.writes);
    }

    // Compute execution order (topological sort)
    const execution_order = try computeExecutionOrder(allocator, metadata_list.items);
    defer allocator.free(execution_order);

    // Write SystemMetadata.zig
    try writeSystemMetadataFile(allocator, metadata_list.items, execution_order, project_dir);
    print("  Generated SystemMetadata.zig\n", .{});
}

fn deduplicateComponents(allocator: std.mem.Allocator, list: *ArrayList([]const u8)) !void {
    if (list.items.len == 0) return;

    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    var unique: ArrayList([]const u8) = .empty;
    errdefer unique.deinit(allocator);

    for (list.items) |item| {
        if (!seen.contains(item)) {
            try seen.put(item, {});
            try unique.append(allocator, item);
        } else {
            // Free duplicate
            allocator.free(item);
        }
    }

    // Replace list contents with unique items
    list.deinit(allocator);
    list.* = unique;
}

fn computeExecutionOrder(allocator: std.mem.Allocator, systems: []const SystemMetadataInfo) ![]usize {
    const n = systems.len;
    var result = try allocator.alloc(usize, n);
    errdefer allocator.free(result);

    if (n == 0) return result;

    // Build dependency graph
    var in_degree = try allocator.alloc(usize, n);
    defer allocator.free(in_degree);
    @memset(in_degree, 0);

    var dependencies = try allocator.alloc(ArrayList(usize), n);
    defer {
        for (dependencies) |*list| list.deinit(allocator);
        allocator.free(dependencies);
    }
    for (0..n) |i| {
        dependencies[i] = .empty;
    }

    // Build dependency edges
    for (systems, 0..) |sys, i| {
        // runs_before: i must run before these systems
        for (sys.runs_before.items) |target_name| {
            for (systems, 0..) |other, j| {
                if (std.mem.eql(u8, target_name, other.name)) {
                    try dependencies[j].append(allocator, i); // j depends on i
                    in_degree[j] += 1;
                    break;
                }
            }
        }

        // runs_after: i must run after these systems
        for (sys.runs_after.items) |dep_name| {
            for (systems, 0..) |other, j| {
                if (std.mem.eql(u8, dep_name, other.name)) {
                    try dependencies[i].append(allocator, j); // i depends on j
                    in_degree[i] += 1;
                    break;
                }
            }
        }

        // Component dependencies: if j writes what i reads, i depends on j
        for (systems, 0..) |other, j| {
            if (i == j) continue;

            // Skip if j explicitly runs_before i (would create redundant edge)
            var j_runs_before_i = false;
            for (other.runs_before.items) |target| {
                if (std.mem.eql(u8, target, sys.name)) {
                    j_runs_before_i = true;
                    break;
                }
            }

            // Skip if i explicitly runs_before j (would create backwards edge)
            var i_runs_before_j = false;
            for (sys.runs_before.items) |target| {
                if (std.mem.eql(u8, target, other.name)) {
                    i_runs_before_j = true;
                    break;
                }
            }

            // If there's already an explicit ordering, skip component dependency
            if (j_runs_before_i or i_runs_before_j) continue;

            // Check if other writes components that sys reads
            var has_dependency = false;
            for (other.writes.items) |write_comp| {
                for (sys.reads.items) |read_comp| {
                    if (std.mem.eql(u8, write_comp, read_comp)) {
                        has_dependency = true;
                        break;
                    }
                }
                if (has_dependency) break;
            }

            if (has_dependency) {
                // Check if already added
                var already_added = false;
                for (dependencies[i].items) |dep| {
                    if (dep == j) {
                        already_added = true;
                        break;
                    }
                }
                if (!already_added) {
                    try dependencies[i].append(allocator, j);
                    in_degree[i] += 1;
                }
            }
        }
    }

    // Kahn's algorithm for topological sort
    var queue: ArrayList(usize) = .empty;
    defer queue.deinit(allocator);

    for (0..n) |i| {
        if (in_degree[i] == 0) {
            try queue.append(allocator, i);
        }
    }

    var result_idx: usize = 0;
    while (queue.items.len > 0) {
        const current = queue.orderedRemove(0);
        result[result_idx] = current;
        result_idx += 1;

        // Update dependencies
        for (0..n) |i| {
            for (dependencies[i].items) |dep| {
                if (dep == current) {
                    in_degree[i] -= 1;
                    if (in_degree[i] == 0) {
                        try queue.append(allocator, i);
                    }
                    break;
                }
            }
        }
    }

    const has_cycle = result_idx != n;
    if (has_cycle) {
        print("  ERROR: Circular dependency detected!\n", .{});
        print("  Systems involved in cycle:\n", .{});
        var cycle_count: usize = 0;
        for (0..n) |i| {
            if (in_degree[i] > 0) {
                print("    - {s} (waiting on: ", .{systems[i].name});
                var first = true;
                for (dependencies[i].items) |dep_idx| {
                    if (in_degree[dep_idx] > 0) {
                        if (!first) print(", ", .{});
                        print("{s}", .{systems[dep_idx].name});
                        first = false;
                    }
                }
                print(")\n", .{});
                cycle_count += 1;
            }
        }
        if (cycle_count > 0) {
            print("  Fix: Add runs_before/runs_after declarations to break the cycle\n", .{});
            print("  Falling back to alphabetical order\n", .{});
        }
        // Return alphabetical order as fallback
        for (0..n) |i| {
            result[i] = i;
        }
    }

    return result;
}

fn writeSystemMetadataFile(allocator: std.mem.Allocator, metadata: []const SystemMetadataInfo, execution_order: []const usize, project_dir: []const u8) !void {
    const metadata_path = try std.fs.path.join(allocator, &.{ project_dir, "src", "registries", "SystemMetadata.zig" });
    defer allocator.free(metadata_path);

    var fw = FileWriter{ .filePath = metadata_path };
    defer fw.deinit(allocator);

    try fw.writeLine(allocator, "// Generated by: zig build registry");
    try fw.writeLine(allocator, "// System dependency metadata extracted via static analysis");
    try fw.writeLine(allocator, "");
    try fw.writeLine(allocator, "pub const SystemMetadata = struct {");
    try fw.writeLine(allocator, "    name: []const u8,");
    try fw.writeLine(allocator, "    phase: []const u8,");
    try fw.writeLine(allocator, "    reads: []const []const u8,");
    try fw.writeLine(allocator, "    writes: []const []const u8,");
    try fw.writeLine(allocator, "    runs_before: []const []const u8,");
    try fw.writeLine(allocator, "    runs_after: []const []const u8,");
    try fw.writeLine(allocator, "    has_queries: bool,");
    try fw.writeLine(allocator, "};");
    try fw.writeLine(allocator, "");
    try fw.writeLine(allocator, "pub const all_metadata: []const SystemMetadata = &.{");

    for (metadata) |meta| {
        try fw.writeLine(allocator, "    .{");
        try fw.writeFmt(allocator, "        .name = \"{s}\",\n", .{meta.name});
        try fw.writeFmt(allocator, "        .phase = \"{s}\",\n", .{meta.phase});

        // Reads
        try fw.write(allocator, "        .reads = &.{");
        for (meta.reads.items, 0..) |comp, i| {
            if (i > 0) try fw.write(allocator, ", ");
            try fw.writeFmt(allocator, "\"{s}\"", .{comp});
        }
        try fw.writeLine(allocator, "},");

        // Writes
        try fw.write(allocator, "        .writes = &.{");
        for (meta.writes.items, 0..) |comp, i| {
            if (i > 0) try fw.write(allocator, ", ");
            try fw.writeFmt(allocator, "\"{s}\"", .{comp});
        }
        try fw.writeLine(allocator, "},");

        // Runs before
        try fw.write(allocator, "        .runs_before = &.{");
        for (meta.runs_before.items, 0..) |sys, i| {
            if (i > 0) try fw.write(allocator, ", ");
            try fw.writeFmt(allocator, "\"{s}\"", .{sys});
        }
        try fw.writeLine(allocator, "},");

        // Runs after
        try fw.write(allocator, "        .runs_after = &.{");
        for (meta.runs_after.items, 0..) |sys, i| {
            if (i > 0) try fw.write(allocator, ", ");
            try fw.writeFmt(allocator, "\"{s}\"", .{sys});
        }
        try fw.writeLine(allocator, "},");

        try fw.writeFmt(allocator, "        .has_queries = {s},\n", .{if (meta.has_queries) "true" else "false"});
        try fw.writeLine(allocator, "    },");
    }

    try fw.writeLine(allocator, "};");
    try fw.writeLine(allocator, "");

    // Write execution order (topologically sorted indices)
    try fw.writeLine(allocator, "/// Pre-computed execution order based on dependencies");
    try fw.write(allocator, "pub const execution_order: []const usize = &.{");
    for (execution_order, 0..) |idx, i| {
        if (i > 0) try fw.write(allocator, ", ");
        try fw.writeFmt(allocator, "{d}", .{idx});
    }
    try fw.writeLine(allocator, "};");

    try fw.saveFile();
}

fn writeEmptySystemMetadata(allocator: std.mem.Allocator, project_dir: []const u8) !void {
    const metadata_path = try std.fs.path.join(allocator, &.{ project_dir, "src", "registries", "SystemMetadata.zig" });
    defer allocator.free(metadata_path);

    var fw = FileWriter{ .filePath = metadata_path };
    defer fw.deinit(allocator);

    try fw.writeLine(allocator, "// Generated by: zig build registry");
    try fw.writeLine(allocator, "// System dependency metadata extracted via static analysis");
    try fw.writeLine(allocator, "");
    try fw.writeLine(allocator, "pub const SystemMetadata = struct {");
    try fw.writeLine(allocator, "    name: []const u8,");
    try fw.writeLine(allocator, "    phase: []const u8,");
    try fw.writeLine(allocator, "    reads: []const []const u8,");
    try fw.writeLine(allocator, "    writes: []const []const u8,");
    try fw.writeLine(allocator, "    runs_before: []const []const u8,");
    try fw.writeLine(allocator, "    runs_after: []const []const u8,");
    try fw.writeLine(allocator, "    has_queries: bool,");
    try fw.writeLine(allocator, "};");
    try fw.writeLine(allocator, "");
    try fw.writeLine(allocator, "pub const all_metadata: []const SystemMetadata = &.{};");
    try fw.writeLine(allocator, "");
    try fw.writeLine(allocator, "/// Pre-computed execution order based on dependencies");
    try fw.writeLine(allocator, "pub const execution_order: []const usize = &.{};");

    try fw.saveFile();
}

/// Ensure Phases.zig exists with default template if missing
/// This is a user-editable file, so we only create it if it doesn't exist
fn ensurePhasesFile(allocator: std.mem.Allocator, project_dir: []const u8) !void {
    const phases_path = try std.fs.path.join(allocator, &.{ project_dir, "src", "registries", "Phases.zig" });
    defer allocator.free(phases_path);

    // Check if file already exists
    std.fs.cwd().access(phases_path, .{}) catch {
        // File doesn't exist, create it with default template
        print("Creating default Phases.zig...\n", .{});

        var fw = FileWriter{ .filePath = phases_path };
        defer fw.deinit(allocator);

        try fw.writeLine(allocator, "// User-defined execution phases");
        try fw.writeLine(allocator, "// Edit this file to define your game's phase structure");
        try fw.writeLine(allocator, "");
        try fw.writeLine(allocator, "pub const Phase = enum {");
        try fw.writeLine(allocator, "    PreUpdate,");
        try fw.writeLine(allocator, "    Update,");
        try fw.writeLine(allocator, "    PostUpdate,");
        try fw.writeLine(allocator, "    Render,");
        try fw.writeLine(allocator, "};");
        try fw.writeLine(allocator, "");
        try fw.writeLine(allocator, "/// Order in which phases execute");
        try fw.writeLine(allocator, "pub const phase_sequence: []const Phase = &.{");
        try fw.writeLine(allocator, "    .PreUpdate,");
        try fw.writeLine(allocator, "    .Update,");
        try fw.writeLine(allocator, "    .PostUpdate,");
        try fw.writeLine(allocator, "    .Render,");
        try fw.writeLine(allocator, "};");

        try fw.saveFile();
        print("  Created: {s}\n\n", .{phases_path});
        return;
    };

    // File exists, nothing to do
}
