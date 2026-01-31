const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Raylib dependency
    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib = raylib_dep.module("raylib");
    const raylib_artifact = raylib_dep.artifact("raylib");

    const mod = b.addModule("Prescient", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "Prescient",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "Prescient", .module = mod },
                .{ .name = "raylib", .module = raylib },
            },
        }),
    });

    exe.linkLibrary(raylib_artifact);
    b.installArtifact(exe);

    // Registry builder: zig build registry
    const registry_builder = b.addExecutable(.{
        .name = "registry-builder",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/build_tools/registry_builder.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const registry_step = b.step("registry", "Regenerate ComponentRegistry and SystemRegistry");
    const run_registry = b.addRunArtifact(registry_builder);
    run_registry.addArg(b.pathFromRoot("."));
    registry_step.dependOn(&run_registry.step);

    // System sequence generator
    const system_seq_gen = b.addExecutable(.{
        .name = "system-seq-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/build_tools/system_sequence_generator.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "SystemMetadata", .module = b.addModule("SystemMetadata", .{
                    .root_source_file = b.path("src/registries/SystemMetadata.zig"),
                    .target = target,
                }) },
                .{ .name = "Phases", .module = b.addModule("Phases", .{
                    .root_source_file = b.path("src/registries/Phases.zig"),
                    .target = target,
                }) },
            },
        }),
    });
    system_seq_gen.step.dependOn(&run_registry.step);

    const run_system_seq_auto = b.addRunArtifact(system_seq_gen);
    run_system_seq_auto.addArg(b.pathFromRoot("."));

    // Auto-run registry builder and system sequence generator before compiling
    exe.step.dependOn(&run_system_seq_auto.step);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    mod_tests.step.dependOn(&run_registry.step);

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // =========================================================================
    // Build Tools - Code generators for components, systems, and registries
    // =========================================================================

    const update = b.addExecutable(.{
        .name = "update",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/build_tools/update.zig"),
            .target = target,
            .optimize = optimize,
        })
    });

    const update_step = b.step("update", "Update project to the newest version of Prescient");
    const run_update = b.addRunArtifact(update);
    run_update.addArg(b.pathFromRoot("."));
    update_step.dependOn(&run_update.step);

    // Component generator: zig build component -- MyComponent
    const component_gen = b.addExecutable(.{
        .name = "component-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/build_tools/component_generator.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const component_step = b.step("component", "Generate a new component template");
    const run_component_gen = b.addRunArtifact(component_gen);
    run_component_gen.addArg(b.pathFromRoot("."));
    if (b.args) |args| run_component_gen.addArgs(args);
    component_step.dependOn(&run_component_gen.step);

    // System generator: zig build system -- MySystem
    const system_gen = b.addExecutable(.{
        .name = "system-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/build_tools/system_generator.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const system_step = b.step("system", "Generate a new system template");
    const run_system_gen = b.addRunArtifact(system_gen);
    run_system_gen.addArg(b.pathFromRoot("."));
    if (b.args) |args| run_system_gen.addArgs(args);
    system_step.dependOn(&run_system_gen.step);

    // Pool generator: zig build pool -- MyPool
    const pool_gen = b.addExecutable(.{
        .name = "pool-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/build_tools/pool_generator.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const pool_step = b.step("pool", "Generate a new pool template");
    const run_pool_gen = b.addRunArtifact(pool_gen);
    run_pool_gen.addArg(b.pathFromRoot("."));
    if (b.args) |args| run_pool_gen.addArgs(args);
    pool_step.dependOn(&run_pool_gen.step);

    // Factory generator: zig build factory -- MyFactory
    const factory_gen = b.addExecutable(.{
        .name = "factory-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/build_tools/factory_generator.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const factory_step = b.step("factory", "Generate a new factory template");
    const run_factory_gen = b.addRunArtifact(factory_gen);
    run_factory_gen.addArg(b.pathFromRoot("."));
    if (b.args) |args| run_factory_gen.addArgs(args);
    factory_step.dependOn(&run_factory_gen.step);

    // =========================================================================
    // System graph visualizer: zig build system-graph
    // =========================================================================

    // Create a module for the system metadata
    const system_metadata_mod = b.addModule("SystemMetadata", .{
        .root_source_file = b.path("src/registries/SystemMetadata.zig"),
        .target = target,
    });

    const system_graph = b.addExecutable(.{
        .name = "system-graph",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/build_tools/system_graph.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "SystemMetadata", .module = system_metadata_mod },
            },
        }),
    });
    // System graph needs registry to run first (to generate SystemMetadata.zig)
    system_graph.step.dependOn(&run_registry.step);

    const graph_step = b.step("system-graph", "Print system execution order and dependencies");
    const run_graph = b.addRunArtifact(system_graph);
    if (b.args) |args| run_graph.addArgs(args);
    graph_step.dependOn(&run_graph.step);

    // =========================================================================
    // System sequence generator: zig build system-seq
    // =========================================================================

    const system_seq_step = b.step("system-seq", "Generate SystemSequence.zig with pre-computed execution order");
    const run_system_seq_manual = b.addRunArtifact(system_seq_gen);
    run_system_seq_manual.addArg(b.pathFromRoot("."));
    system_seq_step.dependOn(&run_system_seq_manual.step);

    // =========================================================================
    // Raylib installer: zig build raylib-install
    // =========================================================================

    const raylib_installer = b.addExecutable(.{
        .name = "raylib-installer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/build_tools/raylib_installer.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const raylib_step = b.step("raylib-install", "Install raylib-zig bindings");
    const run_raylib_installer = b.addRunArtifact(raylib_installer);
    run_raylib_installer.addArg(b.pathFromRoot("."));
    raylib_step.dependOn(&run_raylib_installer.step);
}
