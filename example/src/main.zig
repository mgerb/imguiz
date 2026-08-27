const std = @import("std");
const builtin = @import("builtin");
const UI = @import("./ui.zig").UI;
const Vulkan = @import("./vulkan.zig").Vulkan;

const pipewire = if (builtin.os.tag == .linux) @import("pipewire") else struct {};

// Pipewire is statically linked, but we aren't actually using it in here.
// We must stub it in here so that it doesn't get optimized away.
comptime {
    _ = pipewire;
}

pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var extensions = try UI.getSDLVulkanExtensions(allocator);
    defer extensions.deinit(allocator);
    const vulkan = try Vulkan.init(allocator, init.io, extensions.items);
    defer vulkan.deinit();

    const ui = try UI.init(allocator, vulkan);
    defer ui.deinit();
}
