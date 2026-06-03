const std = @import("std");

fn buildFreetype(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const freetype_dep = b.dependency("freetype", .{});

    const freetype_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // Override ftmodule.h with our own.
    // See the comment in: ./src/freetype/include/freetype/config/ftmodule.h
    freetype_module.addIncludePath(b.path("src/freetype/include"));
    freetype_module.addIncludePath(freetype_dep.path("include"));

    const freetype_c_flags = &.{
        "-DFT2_BUILD_LIBRARY",
    };
    freetype_module.addCSourceFiles(.{
        .root = freetype_dep.path(""),
        .files = &.{
            "src/base/ftbase.c",
            "src/base/ftbbox.c",
            "src/base/ftbitmap.c",
            "src/base/ftbdf.c",
            "src/base/ftcid.c",
            "src/base/ftcolor.c",
            "src/base/ftdebug.c",
            "src/base/ftfntfmt.c",
            "src/base/ftfstype.c",
            "src/base/ftgasp.c",
            "src/base/ftglyph.c",
            "src/base/ftgxval.c",
            "src/base/ftinit.c",
            "src/base/ftlcdfil.c",
            "src/base/ftmm.c",
            "src/base/ftotval.c",
            "src/base/ftpatent.c",
            "src/base/ftpfr.c",
            "src/base/ftstroke.c",
            "src/base/ftsynth.c",
            "src/base/ftsystem.c",
            "src/base/fttype1.c",
            "src/base/ftwinfnt.c",
            "src/autofit/autofit.c",
            "src/cff/cff.c",
            "src/gzip/ftgzip.c",
            "src/psaux/psaux.c",
            "src/pshinter/pshinter.c",
            "src/psnames/psnames.c",
            "src/raster/raster.c",
            "src/sfnt/sfnt.c",
            "src/smooth/smooth.c",
            "src/truetype/truetype.c",
        },
        .flags = freetype_c_flags,
    });

    return b.addLibrary(.{
        .name = "freetype",
        .linkage = .static,
        .root_module = freetype_module,
    });
}

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
    const freetype = b.option(bool, "freetype", "Enable FreeType font rasterization") orelse false;

    if (generate_bindings != null and generate_bindings.?) {
        generateBindings(b, target, optimize);
    } else {
        const module = b.addModule("imguiz", .{
            .root_source_file = b.path("src/imguiz.zig"),
            .target = target,
            .optimize = optimize,
            .link_libcpp = true,
        });
        module.addCMacro("IMGUI_USE_WCHAR32", "1");

        const vulkan = b.dependency("vulkan_headers", .{});
        module.addIncludePath(vulkan.path("include"));

        // SDL3
        const sdl = b.dependency("sdl", .{
            .target = target,
            .optimize = optimize,
            .preferred_linkage = .static,
        });
        const sdl_lib = sdl.artifact("SDL3");
        module.addIncludePath(sdl_lib.getEmittedIncludeTree());
        module.linkLibrary(sdl_lib);

        module.addIncludePath(b.path("generated"));
        module.addIncludePath(b.path("generated/backends"));
        module.addCSourceFile(.{ .file = b.path("generated/imgui.cpp") });
        module.addCSourceFile(.{ .file = b.path("generated/imgui_widgets.cpp") });
        module.addCSourceFile(.{ .file = b.path("generated/imgui_tables.cpp") });
        module.addCSourceFile(.{ .file = b.path("generated/imgui_draw.cpp") });
        module.addCSourceFile(.{ .file = b.path("generated/imgui_demo.cpp") });
        module.addCSourceFile(.{ .file = b.path("generated/backends/imgui_impl_sdl3.cpp") });
        module.addCSourceFile(.{ .file = b.path("generated/backends/imgui_impl_vulkan.cpp") });
        module.addCSourceFile(.{ .file = b.path("generated/dcimgui.cpp") });
        module.addCSourceFile(.{ .file = b.path("generated/dcimgui_internal.cpp") });
        module.addCSourceFile(.{ .file = b.path("generated/backends/dcimgui_impl_sdl3.cpp") });
        module.addCSourceFile(.{ .file = b.path("generated/backends/dcimgui_impl_vulkan.cpp") });

        if (freetype) {
            const freetype_dep = b.dependency("freetype", .{});
            const freetype_lib = buildFreetype(b, target, optimize);

            module.addCMacro("IMGUI_ENABLE_FREETYPE", "1");
            module.addIncludePath(b.path("src/freetype-config"));
            module.addIncludePath(freetype_dep.path("include"));
            module.addCSourceFile(.{ .file = b.path("generated/misc/freetype/imgui_freetype.cpp") });
            module.linkLibrary(freetype_lib);
        }
    }
}
