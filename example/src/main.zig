const std = @import("std");
const UI = @import("./ui.zig").UI;
const Vulkan = @import("./vulkan.zig").Vulkan;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var extensions = try UI.getSDLVulkanExtensions(allocator);
    defer extensions.deinit(allocator);
    const vulkan = try Vulkan.init(allocator, extensions.items);
    defer vulkan.deinit();

    const ui = try UI.init(allocator, vulkan);
    defer ui.deinit();
}
