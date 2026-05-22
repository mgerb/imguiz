const std = @import("std");

const TMP_DIR = "tmp";

const IMGUI_VERSION = "v1.92.7-docking";
const DEAR_BINDINGS_VERSION = "05f6a235c2d1963b17d98730b6a9d09f705e001c";

fn runCommand(opts: struct {
    args: []const []const u8,
    allocator: std.mem.Allocator,
    io: std.Io,
    cwd: ?[]const u8 = null,
}) !void {
    const command = try std.mem.join(opts.allocator, " ", opts.args);
    defer opts.allocator.free(command);
    std.debug.print("\n--------------------\n{s}\n--------------------\n\n", .{command});

    var child = try std.process.spawn(opts.io, .{
        .argv = opts.args,
        .cwd = if (opts.cwd) |cwd| .{ .path = cwd } else .inherit,
    });
    const term = try child.wait(opts.io);

    switch (term) {
        .exited => |val| {
            if (val != 0) {
                std.debug.print("exit code: {}\n", .{val});
                return error.bad_exit;
            }
        },
        .signal => return error.signal,
        .stopped => return error.stopped,
        .unknown => return error.unknown,
    }
}

pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const io = init.io;
    const cwd = std.Io.Dir.cwd();

    try cwd.deleteTree(io, "src/generated");
    try cwd.deleteTree(io, TMP_DIR);

    cwd.createDir(io, TMP_DIR, .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };

    try runCommand(.{
        .args = &.{ "git", "clone", "https://github.com/dearimgui/dear_bindings" },
        .allocator = allocator,
        .io = io,
        .cwd = TMP_DIR,
    });

    try runCommand(.{
        .args = &.{ "git", "checkout", DEAR_BINDINGS_VERSION },
        .allocator = allocator,
        .io = io,
        .cwd = TMP_DIR ++ "/dear_bindings",
    });

    try runCommand(.{
        .args = &.{
            "git",
            "clone",
            "--single-branch",
            "--branch",
            "docking",
            "https://github.com/ocornut/imgui",
        },
        .allocator = allocator,
        .io = io,
        .cwd = TMP_DIR,
    });

    try runCommand(.{
        .args = &.{ "git", "checkout", IMGUI_VERSION },
        .allocator = allocator,
        .io = io,
        .cwd = TMP_DIR ++ "/imgui",
    });

    try runCommand(.{
        .args = &.{ "chmod", "+x", "BuildAllBindings.sh" },
        .allocator = allocator,
        .io = io,
        .cwd = TMP_DIR ++ "/dear_bindings",
    });

    try runCommand(.{
        .args = &.{ "bash", "BuildAllBindings.sh" },
        .allocator = allocator,
        .io = io,
        .cwd = TMP_DIR ++ "/dear_bindings",
    });

    try runCommand(.{
        .args = &.{ "sh", "-c", "cp " ++ TMP_DIR ++ "/imgui/*.h " ++ TMP_DIR ++ "/dear_bindings/generated" },
        .allocator = allocator,
        .io = io,
    });

    try runCommand(.{
        .args = &.{ "sh", "-c", "cp " ++ TMP_DIR ++ "/imgui/*.cpp " ++ TMP_DIR ++ "/dear_bindings/generated" },
        .allocator = allocator,
        .io = io,
    });

    try runCommand(.{
        .args = &.{ "sh", "-c", "cp -R " ++ TMP_DIR ++ "/imgui/backends " ++ TMP_DIR ++ "/dear_bindings/generated" },
        .allocator = allocator,
        .io = io,
    });

    try runCommand(.{
        .args = &.{ "sh", "-c", "cp -R " ++ TMP_DIR ++ "/imgui/misc " ++ TMP_DIR ++ "/dear_bindings/generated" },
        .allocator = allocator,
        .io = io,
    });

    try runCommand(.{
        .args = &.{ "sh", "-c", "cp -R " ++ TMP_DIR ++ "/dear_bindings/generated ./" },
        .allocator = allocator,
        .io = io,
    });

    std.debug.print("All bindings generated.\n", .{});
}
