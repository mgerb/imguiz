const std = @import("std");
const UI = @import("./ui.zig").UI;
const Vulkan = @import("./vulkan.zig").Vulkan;

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
