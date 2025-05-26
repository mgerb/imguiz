const std = @import("std");

const TMP_DIR = "tmp";

fn cloneDearBindings(allocator: std.mem.Allocator) !void {
    const term = runCommand(&.{ "git", "clone", "https://github.com/dearimgui/dear_bindings" }, allocator);
    std.debug.print("term: {any}\n", .{term});
}

fn cloneDearImgui(allocator: std.mem.Allocator) !void {
    const term = runCommand(&.{ "git", "clone", "https://github.com/ocornut/imgui" }, allocator);
    std.debug.print("term: {any}\n", .{term});
}

fn runCommand(opts: struct {
    args: []const []const u8,
    allocator: std.mem.Allocator,
    cwd: ?[]const u8 = null,
}) !void {
    const command = try std.mem.join(opts.allocator, " ", opts.args);
    defer opts.allocator.free(command);
    std.debug.print("\n--------------------\n{s}\n--------------------\n\n", .{command});

    var child = std.process.Child.init(opts.args, opts.allocator);
    if (opts.cwd) |cwd| {
        child.cwd = cwd;
    }
    try child.spawn();
    const term = try child.wait();

    switch (term) {
        .Exited => |val| {
            if (val != 0) {
                std.debug.print("exit code: {}\n", .{val});
                return error.bad_exit;
            }
        },
        .Signal => return error.signal,
        .Stopped => return error.stopped,
        .Unknown => return error.unknown,
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try std.fs.cwd().deleteTree("src/generated");
    try std.fs.cwd().deleteTree(TMP_DIR);

    std.fs.cwd().makeDir(TMP_DIR) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };

    _ = try runCommand(.{
        .args = &.{ "git", "clone", "https://github.com/dearimgui/dear_bindings" },
        .allocator = allocator,
        .cwd = TMP_DIR,
    });

    _ = try runCommand(.{
        .args = &.{
            "git",
            "clone",
            "--single-branch",
            "--branch",
            "docking",
            "https://github.com/ocornut/imgui",
        },
        .allocator = allocator,
        .cwd = TMP_DIR,
    });

    _ = try runCommand(.{
        .args = &.{ "chmod", "+x", "BuildAllBindings.sh" },
        .allocator = allocator,
        .cwd = TMP_DIR ++ "/dear_bindings",
    });

    _ = try runCommand(.{
        .args = &.{ "bash", "BuildAllBindings.sh" },
        .allocator = allocator,
        .cwd = TMP_DIR ++ "/dear_bindings",
    });

    _ = try runCommand(.{
        .args = &.{ "sh", "-c", "cp " ++ TMP_DIR ++ "/imgui/*.h " ++ TMP_DIR ++ "/dear_bindings/generated" },
        .allocator = allocator,
    });

    _ = try runCommand(.{
        .args = &.{ "sh", "-c", "cp " ++ TMP_DIR ++ "/imgui/*.cpp " ++ TMP_DIR ++ "/dear_bindings/generated" },
        .allocator = allocator,
    });

    _ = try runCommand(.{
        .args = &.{ "sh", "-c", "cp -R " ++ TMP_DIR ++ "/imgui/backends " ++ TMP_DIR ++ "/dear_bindings/generated" },
        .allocator = allocator,
    });

    _ = try runCommand(.{
        .args = &.{ "sh", "-c", "cp -R " ++ TMP_DIR ++ "/imgui/misc " ++ TMP_DIR ++ "/dear_bindings/generated" },
        .allocator = allocator,
    });

    _ = try runCommand(.{
        .args = &.{ "sh", "-c", "cp -R " ++ TMP_DIR ++ "/dear_bindings/generated ./" },
        .allocator = allocator,
    });

    std.debug.print("All bindings generated.\n", .{});
}
