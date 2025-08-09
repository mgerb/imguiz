const std = @import("std");

const vk = @import("vulkan");
const BaseDispatch = vk.BaseWrapper;
const InstanceDispatch = vk.InstanceWrapper;
const DeviceDispatch = vk.DeviceWrapper;
pub const Instance = vk.InstanceProxy;
pub const Device = vk.DeviceProxy;
pub const CommandBuffer = vk.CommandBufferProxy;

pub const API_VERSION = vk.API_VERSION_1_4;

const INSTANCE_EXTENSIONS = [_][*:0]const u8{
    vk.extensions.khr_get_physical_device_properties_2.name,
};

const DEVICE_EXTENSIONS = [_][*:0]const u8{
    vk.extensions.khr_dynamic_rendering.name,
    vk.extensions.khr_synchronization_2.name,
    vk.extensions.khr_swapchain.name,
};

pub extern fn vkGetInstanceProcAddr(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;

const QueueAllocation = struct {
    graphics_family: u32,
};

pub const DeviceCandidate = struct {
    pdev: vk.PhysicalDevice,
    props: vk.PhysicalDeviceProperties,
    queues: QueueAllocation,
};

pub const Queue = struct {
    handle: vk.Queue,
    family: u32,
    mutex: std.Thread.Mutex = .{},

    pub fn init(device: Device, family: u32) Queue {
        return .{
            .handle = device.getDeviceQueue(family, 0),
            .family = family,
        };
    }
};

pub const Vulkan = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    vkb: BaseDispatch,
    instance: Instance,
    device: Device,
    debug_messenger: ?vk.DebugUtilsMessengerEXT,
    graphics_queue: Queue,
    physical_device: vk.PhysicalDevice,
    props: vk.PhysicalDeviceProperties,
    mem_props: vk.PhysicalDeviceMemoryProperties,

    command_pool: vk.CommandPool,
    descriptor_pool: vk.DescriptorPool,

    pub fn init(
        allocator: std.mem.Allocator,
        extra_instance_extensions: ?[][*:0]const u8,
    ) !*Self {
        const vkbd = BaseDispatch.load(vkGetInstanceProcAddr);

        const app_info: vk.ApplicationInfo = .{
            .p_application_name = "imguiz",
            .application_version = @bitCast(API_VERSION),
            .p_engine_name = "imguiz",
            .engine_version = @bitCast(API_VERSION),
            .api_version = @bitCast(API_VERSION),
        };

        var extension_names = std.ArrayList([*:0]const u8).init(allocator);
        defer extension_names.deinit();

        try extension_names.appendSlice(&INSTANCE_EXTENSIONS);

        if (extra_instance_extensions) |extensions| {
            for (extensions) |extension| {
                try extension_names.append(std.mem.span(extension));
            }
        }

        try extension_names.append(vk.extensions.ext_debug_utils.name);

        const validation_layers = [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};
        const enabled_layers: []const [*:0]const u8 = &validation_layers;

        const instance_def = try vkbd.createInstance(&.{
            .p_application_info = &app_info,

            .enabled_extension_count = @intCast(extension_names.items.len),
            .pp_enabled_extension_names = extension_names.items.ptr,

            .enabled_layer_count = @intCast(enabled_layers.len),
            .pp_enabled_layer_names = enabled_layers.ptr,
        }, null);

        const vki = try allocator.create(InstanceDispatch);
        errdefer allocator.destroy(vki);
        vki.* = InstanceDispatch.load(instance_def, vkbd.dispatch.vkGetInstanceProcAddr.?);
        const instance = Instance.init(instance_def, vki);
        errdefer instance.destroyInstance(null);

        var debug_messenger: ?vk.DebugUtilsMessengerEXT = null;

        debug_messenger = try instance.createDebugUtilsMessengerEXT(&.{
            .message_severity = .{
                .error_bit_ext = true,
                .warning_bit_ext = true,
            },
            .message_type = .{
                .general_bit_ext = true,
                .validation_bit_ext = true,
                .performance_bit_ext = true,
                .device_address_binding_bit_ext = false,
            },
            .pfn_user_callback = debugCallback,
        }, null);
        errdefer {
            if (debug_messenger) |dm| {
                instance.destroyDebugUtilsMessengerEXT(dm, null);
            }
        }

        const candidate = try pickPhysicalDevice(instance, allocator);

        const pdev = candidate.pdev;
        const props = candidate.props;
        const mem_props = instance.getPhysicalDeviceMemoryProperties(pdev);

        const device_candidate = try initializeCandidate(instance, candidate);
        const vkd = try allocator.create(DeviceDispatch);
        errdefer allocator.destroy(vkd);
        vkd.* = DeviceDispatch.load(device_candidate, instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
        const device = Device.init(device_candidate, vkd);
        errdefer device.destroyDevice(null);

        const graphics_queue = Queue.init(device, candidate.queues.graphics_family);

        const pool_size = vk.DescriptorPoolSize{
            .type = .combined_image_sampler,
            .descriptor_count = 1,
        };

        const pool_info = vk.DescriptorPoolCreateInfo{
            .flags = .{ .free_descriptor_set_bit = true },
            .max_sets = 1,
            .p_pool_sizes = @ptrCast(&pool_size),
            .pool_size_count = 1,
        };

        // used for sdl window
        const descriptor_pool = try device.createDescriptorPool(&pool_info, null);
        errdefer device.destroyDescriptorPool(descriptor_pool, null);

        const command_pool = try device.createCommandPool(&.{
            .queue_family_index = graphics_queue.family,
            .flags = .{ .reset_command_buffer_bit = true },
        }, null);
        errdefer device.destroyCommandPool(command_pool, null);

        // We use an allocator here because we don't want the
        // reference to change when we return this object.
        const self = try allocator.create(Self);
        self.* = Self{
            .allocator = allocator,
            .vkb = vkbd,
            .instance = instance,
            .debug_messenger = debug_messenger,
            .device = device,
            .graphics_queue = graphics_queue,
            .physical_device = pdev,
            .props = props,
            .mem_props = mem_props,
            .command_pool = command_pool,
            .descriptor_pool = descriptor_pool,
        };

        std.debug.print("Using device: {s}\n", .{self.props.device_name});

        return self;
    }

    fn pickPhysicalDevice(
        instance: Instance,
        allocator: std.mem.Allocator,
    ) !DeviceCandidate {
        const pdevs = try instance.enumeratePhysicalDevicesAlloc(allocator);
        defer allocator.free(pdevs);

        for (pdevs) |pdev| {
            if (try checkSuitable(instance, pdev, allocator)) |candidate| {
                return candidate;
            }
        }

        return error.NoSuitableDevice;
    }

    fn debugCallback(
        message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
        message_types: vk.DebugUtilsMessageTypeFlagsEXT,
        p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
        p_user_data: ?*anyopaque,
    ) callconv(vk.vulkan_call_conv) vk.Bool32 {
        _ = message_severity;
        _ = message_types;
        _ = p_user_data;
        b: {
            const msg = (p_callback_data orelse break :b).p_message orelse break :b;
            std.log.scoped(.validation).warn("{s}", .{msg});
            return vk.FALSE;
        }
        std.log.scoped(.validation).warn("unrecognized validation layer debug message", .{});
        return vk.FALSE;
    }

    fn checkSuitable(
        instance: Instance,
        pdev: vk.PhysicalDevice,
        allocator: std.mem.Allocator,
    ) !?DeviceCandidate {
        if (!try checkDeviceExtensionSupport(instance, pdev, allocator)) {
            return null;
        }

        if (try allocateQueues(instance, pdev, allocator)) |allocation| {
            const props = instance.getPhysicalDeviceProperties(pdev);
            return DeviceCandidate{
                .pdev = pdev,
                .props = props,
                .queues = allocation,
            };
        }

        return null;
    }

    fn extensionEnabled(
        instance: Instance,
        pdev: vk.PhysicalDevice,
        allocator: std.mem.Allocator,
        extension: [*:0]const u8,
    ) !bool {
        const propsv = try instance.enumerateDeviceExtensionPropertiesAlloc(pdev, null, allocator);
        defer allocator.free(propsv);
        for (propsv) |props| {
            if (std.mem.eql(u8, std.mem.span(extension), std.mem.sliceTo(&props.extension_name, 0))) {
                return true;
            }
        }
        return false;
    }

    fn checkDeviceExtensionSupport(
        instance: Instance,
        pdev: vk.PhysicalDevice,
        allocator: std.mem.Allocator,
    ) !bool {
        for (DEVICE_EXTENSIONS) |ext| {
            if (!try extensionEnabled(instance, pdev, allocator, ext)) {
                return false;
            }
        }

        return true;
    }

    fn allocateQueues(
        instance: Instance,
        pdev: vk.PhysicalDevice,
        allocator: std.mem.Allocator,
    ) !?QueueAllocation {
        const families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(pdev, allocator);
        defer allocator.free(families);

        var graphics_family: ?u32 = null;

        for (families, 0..) |properties, i| {
            const family: u32 = @intCast(i);

            if (graphics_family == null and properties.queue_flags.graphics_bit) {
                graphics_family = family;
            }
        }

        if (graphics_family != null) {
            return QueueAllocation{
                .graphics_family = graphics_family.?,
            };
        }

        return null;
    }

    fn initializeCandidate(instance: Instance, candidate: DeviceCandidate) !vk.Device {
        const priority = [_]f32{1};
        const qci = [_]vk.DeviceQueueCreateInfo{
            .{
                .queue_family_index = candidate.queues.graphics_family,
                .queue_count = 1,
                .p_queue_priorities = &priority,
            },
        };

        const queue_count: u32 = 1;

        const synchronization2_features = vk.PhysicalDeviceSynchronization2Features{
            .synchronization_2 = vk.TRUE,
        };

        const dynamic_rendering_features = vk.PhysicalDeviceDynamicRenderingFeaturesKHR{
            .p_next = @constCast(@ptrCast(&synchronization2_features)),
            .dynamic_rendering = vk.TRUE,
        };

        return try instance.createDevice(candidate.pdev, &.{
            .p_next = &dynamic_rendering_features,
            .queue_create_info_count = queue_count,
            .p_queue_create_infos = &qci,
            .enabled_extension_count = DEVICE_EXTENSIONS.len,
            .pp_enabled_extension_names = @ptrCast(&DEVICE_EXTENSIONS),
        }, null);
    }

    pub fn allocate(
        self: *Self,
        requirements: vk.MemoryRequirements,
        flags: vk.MemoryPropertyFlags,
        p_next: ?*anyopaque,
    ) !vk.DeviceMemory {
        return try self.device.allocateMemory(&.{
            .allocation_size = requirements.size,
            .memory_type_index = try self.findMemoryTypeIndex(requirements.memory_type_bits, flags),
            .p_next = p_next,
        }, null);
    }

    pub fn findMemoryTypeIndex(self: *Self, memory_type_bits: u32, flags: vk.MemoryPropertyFlags) !u32 {
        for (self.mem_props.memory_types[0..self.mem_props.memory_type_count], 0..) |mem_type, i| {
            if (memory_type_bits & (@as(u32, 1) << @truncate(i)) != 0 and mem_type.property_flags.contains(flags)) {
                return @truncate(i);
            }
        }

        return error.NoSuitableMemoryType;
    }

    pub fn deinit(self: *Self) void {
        self.device.destroyDescriptorPool(self.descriptor_pool, null);

        if (self.debug_messenger) |debug_messenger| {
            self.instance.destroyDebugUtilsMessengerEXT(debug_messenger, null);
        }

        self.device.destroyCommandPool(self.command_pool, null);

        self.device.destroyDevice(null);
        self.instance.destroyInstance(null);

        // allocator destroys
        self.allocator.destroy(self.device.wrapper);
        self.allocator.destroy(self.instance.wrapper);
        self.allocator.destroy(self);
    }
};
