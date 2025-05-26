const std = @import("std");
const imguiz = @import("imguiz");
const UI = @import("./ui.zig").UI;
const Vulkan = @import("./vulkan.zig").Vulkan;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const extensions = try UI.getSDLVulkanExtensions(allocator);
    defer extensions.deinit();
    const vulkan = try Vulkan.init(allocator, extensions.items);
    defer vulkan.deinit();

    const ui = try UI.init(allocator, vulkan);
    defer ui.deinit();
}
