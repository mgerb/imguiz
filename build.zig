const std = @import("std");

fn generateBindings(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "imguiz",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const generate_bindings = b.option(bool, "generate", "Generate the bindings");

    if (generate_bindings != null and generate_bindings.?) {
        generateBindings(b, target, optimize);
    } else {
        const module = b.addModule("imguiz", .{
            .root_source_file = b.path("src/imguiz.zig"),
            .link_libcpp = true,
        });

        const vulkan = b.dependency("vulkan_headers", .{});
        const sdl3 = b.dependency("sdl3", .{});
        module.addIncludePath(vulkan.path("include"));
        module.addIncludePath(sdl3.path("include"));

        module.addIncludePath(b.path("src/generated"));
        module.addIncludePath(b.path("src/generated/backends"));
        module.addCSourceFile(.{ .file = b.path("src/generated/imgui.cpp") });
        module.addCSourceFile(.{ .file = b.path("src/generated/imgui_widgets.cpp") });
        module.addCSourceFile(.{ .file = b.path("src/generated/imgui_tables.cpp") });
        module.addCSourceFile(.{ .file = b.path("src/generated/imgui_draw.cpp") });
        module.addCSourceFile(.{ .file = b.path("src/generated/imgui_demo.cpp") });
        module.addCSourceFile(.{ .file = b.path("src/generated/backends/imgui_impl_sdl3.cpp") });
        module.addCSourceFile(.{ .file = b.path("src/generated/backends/imgui_impl_vulkan.cpp") });
        module.addCSourceFile(.{ .file = b.path("src/generated/dcimgui.cpp") });
        module.addCSourceFile(.{ .file = b.path("src/generated/dcimgui_internal.cpp") });
        module.addCSourceFile(.{ .file = b.path("src/generated/backends/dcimgui_impl_sdl3.cpp") });
        module.addCSourceFile(.{ .file = b.path("src/generated/backends/dcimgui_impl_vulkan.cpp") });
    }
}
