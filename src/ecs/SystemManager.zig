const std = @import("std");
const SR = @import("../registries/SystemRegistry.zig");
const PM = @import("PoolManager.zig");
const SDG = @import("SystemDependencyGraph.zig");
const SystemSequence = @import("../registries/SystemSequence.zig");

fn SystemManagerStorage(comptime systems: []const SR.SystemName) type {
    var fields: [systems.len]std.builtin.Type.StructField = undefined;

    for (systems, 0..) |system, i| {
        const name = @tagName(system);
        const T = SR.getTypeByName(system);

        fields[i] = std.builtin.Type.StructField{
            .name = name,
            .type = T,
            .alignment = @alignOf(T),
            .default_value_ptr = null,
            .is_comptime = false,
        };
    }

    return @Type(std.builtin.Type{
        .@"struct" = .{
            .fields = &fields,
            .backing_integer = null,
            .decls = &.{},
            .is_tuple = false,
            .layout = .auto,
        },
    });
}

pub fn SystemManager(comptime systems: []const SR.SystemName) type {
    const n = systems.len;

    // Build metadata at comptime (O(n) - no deeply nested loops)
    const metadata = SDG.buildSystemMetadata(systems);

    // Detect write-write conflicts at comptime (keeps compile-time errors)
    SDG.detectWriteWriteConflicts(systems, &metadata);

    return struct {
        const Self = @This();

        // Type alias for update function pointers
        const UpdateFn = *const fn (*Self) anyerror!void;

        // Comptime: array of update functions indexed by original system order
        const update_fns_by_index: [n]UpdateFn = blk: {
            var fns: [n]UpdateFn = undefined;
            for (systems, 0..) |sys, i| {
                fns[i] = makeUpdateFn(sys);
            }
            break :blk fns;
        };

        // Comptime: array of update functions sorted by execution order
        const update_fns_sorted: [n]UpdateFn = blk: {
            var fns: [n]UpdateFn = undefined;
            for (SystemSequence.execution_order, 0..) |idx, i| {
                fns[i] = update_fns_by_index[idx];
            }
            break :blk fns;
        };

        // Generate an update function for a specific system at comptime
        fn makeUpdateFn(comptime system: SR.SystemName) UpdateFn {
            return struct {
                fn doUpdate(self: *Self) !void {
                    const SystemType = SR.getTypeByName(system);

                    // Require 'active' field at compile time
                    if (!@hasField(SystemType, "active")) {
                        @compileError("System '" ++ @tagName(system) ++ "' missing required 'active: bool' field");
                    }

                    var sys = &@field(self.storage, @tagName(system));
                    if (sys.active) {
                        try self.updateSystemQueries(sys);
                        try sys.update();
                    }
                }
            }.doUpdate;
        }

        allocator: std.mem.Allocator,
        storage: SystemManagerStorage(systems),
        pool_manager: *PM.PoolManager,

        pub fn init(allocator: std.mem.Allocator, pool_manager: *PM.PoolManager) !Self {
            var self: Self = undefined;
            self.allocator = allocator;
            self.pool_manager = pool_manager;
            var storage: SystemManagerStorage(systems) = undefined;

            inline for (systems, 0..) |_, i| {
                const SystemType = SR.getTypeByName(systems[i]);
                var sys_instance: SystemType = .{
                    .allocator = undefined,
                    .queries = undefined,
                };

                // Set allocator (struct initialization applies defaults for other fields)
                sys_instance.allocator = allocator;

                // Initialize all queries via reflection
                inline for (std.meta.fields(@TypeOf(sys_instance.queries))) |field| {
                    @field(sys_instance.queries, field.name) = try field.type.init(allocator, pool_manager);
                }

                @field(storage, @tagName(systems[i])) = sys_instance;
            }
            self.storage = storage;

            return self;
        }

        pub fn initializeSystems(self: *Self) !void {
            inline for (systems) |system| {
                const SystemType = @TypeOf(@field(self.storage, @tagName(system)));
                if (std.meta.hasFn(SystemType, "init")) {
                    var sys = &@field(self.storage, @tagName(system));
                    try sys.init();
                }
            }
        }

        pub fn deinit(self: *Self) void {
            inline for (systems) |system| {
                var system_instance = &@field(self.storage, @tagName(system));
                inline for (std.meta.fields(@TypeOf(system_instance.queries))) |query_field| {
                    @field(system_instance.queries, query_field.name).deinit();
                }
            }
        }

        pub fn deinitializeSystems(self: *Self) void {
            inline for (systems) |system| {
                const SystemType = @TypeOf(@field(self.storage, @tagName(system)));
                if (std.meta.hasFn(SystemType, "deinit")) {
                    var sys = &@field(self.storage, @tagName(system));
                    sys.deinit();
                }
            }
        }

        fn updateSystemQueries(self: *Self, system: anytype) !void {
            _ = self;
            inline for (std.meta.fields(@TypeOf(system.queries))) |query_field| {
                try @field(system.queries, query_field.name).update();
            }
        }

        pub fn getSystem(self: *Self, comptime system: SR.SystemName) *SR.getTypeByName(system) {
            const field_name = @tagName(system);
            return &@field(self.storage, field_name);
        }

        pub fn setSystemActive(self: *Self, comptime system: SR.SystemName, active: bool) !void {
            var sys = &@field(self.storage, @tagName(system));
            const was_active = sys.active;
            sys.active = active;

            // If activating a previously inactive system, refresh all queries
            // to ensure they include all existing archetypes
            if (active and !was_active) {
                inline for (std.meta.fields(@TypeOf(sys.queries))) |query_field| {
                    try @field(sys.queries, query_field.name).refresh();
                }
            }
        }

        pub fn isSystemActive(self: *Self, comptime system: SR.SystemName) bool {
            const sys = &@field(self.storage, @tagName(system));
            return sys.active;
        }

        pub fn update(self: *Self) !void {
            // Use comptime-sorted function pointers from SystemSequence
            inline for (update_fns_sorted) |update_fn| {
                try update_fn(self);
            }
        }
    };
}
