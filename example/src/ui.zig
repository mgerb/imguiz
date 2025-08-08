const std = @import("std");

const imguiz = @import("imguiz").imguiz;
const vk = @import("vulkan");

const Vulkan = @import("./vulkan.zig").Vulkan;
const API_VERSION = @import("./vulkan.zig").API_VERSION;

const WIDTH = 1600;
const HEIGHT = 1000;

const MIN_IMAGE_COUNT = 2;
var g_PipelineCache: imguiz.VkPipelineCache = std.mem.zeroes(imguiz.VkPipelineCache);

const SDL_INIT_FLAGS = imguiz.SDL_INIT_VIDEO | imguiz.SDL_INIT_GAMEPAD;

pub const UI = struct {
    const Self = @This();

    vulkan: *Vulkan,
    allocator: std.mem.Allocator,

    window: ?*imguiz.struct_SDL_Window = null,
    surface: ?imguiz.VkSurfaceKHR = null,
    vulkan_window: imguiz.ImGui_ImplVulkanH_Window = std.mem.zeroes(imguiz.ImGui_ImplVulkanH_Window),
    swapchain_rebuild: bool = false,

    /// Init SDL and return new UI instance
    pub fn init(
        allocator: std.mem.Allocator,
        vulkan: *Vulkan,
    ) !*Self {
        const self = try allocator.create(Self);

        self.* = Self{
            .allocator = allocator,
            .vulkan = vulkan,
        };

        if (!imguiz.SDL_Init(SDL_INIT_FLAGS)) {
            return error.SDL_initFailure;
        }

        const version = imguiz.SDL_GetVersion();
        std.debug.print("SDL version: {}\n", .{version});

        try self.initVulkan();

        return self;
    }

    /// Caller owns memory
    pub fn getSDLVulkanExtensions(allocator: std.mem.Allocator) !std.ArrayList([*:0]const u8) {
        if (!imguiz.SDL_Init(SDL_INIT_FLAGS)) {
            return error.SDL_initFailure;
        }
        defer imguiz.SDL_Quit();

        var extensions = std.ArrayList([*:0]const u8).init(allocator);
        var extensions_count: u32 = 0;
        const sdl_extensions = imguiz.SDL_Vulkan_GetInstanceExtensions(&extensions_count);
        for (0..extensions_count) |i| try extensions.append(std.mem.span(sdl_extensions[i]));

        return extensions;
    }

    fn initVulkan(self: *Self) !void {
        self.window = imguiz.SDL_CreateWindow("imguiz example", WIDTH, HEIGHT, imguiz.SDL_WINDOW_VULKAN | imguiz.SDL_WINDOW_RESIZABLE | imguiz.SDL_WINDOW_HIGH_PIXEL_DENSITY);
        if (self.window == null) return error.SDL_CreateWindowFailure;
        errdefer {
            if (self.window) |window| {
                imguiz.SDL_DestroyWindow(window);
            }
        }

        var surface: imguiz.VkSurfaceKHR = undefined;

        if (!imguiz.SDL_Vulkan_CreateSurface(self.window, self.vkInstance(), null, &surface)) {
            return error.SDL_Vulkan_CreateSurfaceFailure;
        }
        self.surface = surface;

        if (!imguiz.cImGui_ImplVulkan_LoadFunctions(@bitCast(API_VERSION), loader)) {
            return error.ImGuiVulkanLoadFailure;
        }

        try self.setupVulkanWindow();
        errdefer imguiz.cImGui_ImplVulkanH_DestroyWindow(
            self.vkInstance(),
            self.vkDevice(),
            @ptrCast(&self.vulkan_window),
            null,
        );

        // NOTE: not supported in wayland
        // if (!c.SDL_SetWindowPosition(
        //     self.window.?,
        //     c.SDL_WINDOWPOS_CENTERED,
        //     c.SDL_WINDOWPOS_CENTERED,
        // )) {
        //     return error.SDL_SetWindowPositionFailure;
        // }
        if (!imguiz.SDL_ShowWindow(self.window.?)) {
            return error.SDL_ShowWindowFailure;
        }

        // Setup Dear ImGui context
        if (imguiz.ImGui_CreateContext(null) == null) return error.ImGuiCreateContextFailure;
        errdefer imguiz.ImGui_DestroyContext(null);
        const io = imguiz.ImGui_GetIO();
        io.*.ConfigFlags |= imguiz.ImGuiConfigFlags_NavEnableKeyboard; // Enable Keyboard Controls
        io.*.ConfigFlags |= imguiz.ImGuiConfigFlags_NavEnableGamepad; // Enable Gamepad Controls
        // io.*.ConfigFlags |= c.ImGuiConfigFlags_DockingEnable;
        // io.*.ConfigFlags |= c.ImGuiConfigFlags_ViewportsEnable;

        // Setup Dear ImGui style
        imguiz.ImGui_StyleColorsDark(null);

        const style = imguiz.ImGui_GetStyle();
        if (io.*.ConfigFlags & imguiz.ImGuiConfigFlags_ViewportsEnable > 0) {
            style.*.WindowRounding = 0.0;
            style.*.Colors[imguiz.ImGuiCol_WindowBg].w = 1.0;
        }

        // Setup Platform/Renderer backends
        if (!imguiz.cImGui_ImplSDL3_InitForVulkan(self.window.?)) {
            return error.cImGui_ImplSDL3_InitForVulkanFailure;
        }
        errdefer imguiz.cImGui_ImplSDL3_Shutdown();

        var init_info = imguiz.ImGui_ImplVulkan_InitInfo{};
        init_info.Instance = self.vkInstance();
        init_info.PhysicalDevice = self.vkPhysicalDevice();
        init_info.Device = self.vkDevice();
        init_info.QueueFamily = self.vulkan.graphics_queue.family;
        init_info.Queue = self.vkQueue();
        init_info.PipelineCache = g_PipelineCache;
        init_info.DescriptorPool = self.vkDescriptorPool();
        init_info.RenderPass = self.vulkan_window.RenderPass;
        init_info.Subpass = 0;
        init_info.MinImageCount = MIN_IMAGE_COUNT;
        init_info.ImageCount = self.vulkan_window.ImageCount;
        init_info.MSAASamples = imguiz.VK_SAMPLE_COUNT_1_BIT;
        init_info.Allocator = null;
        init_info.CheckVkResultFn = check_vk_result;
        if (!imguiz.cImGui_ImplVulkan_Init(&init_info)) {
            return error.ImGuiVulkanInitFailure;
        }
        errdefer imguiz.cImGui_ImplVulkan_Shutdown();

        // Load Fonts
        // - If no fonts are loaded, dear imgui will use the default font. You can also load multiple fonts and use ImGui::PushFont()/PopFont() to select them.
        // - AddFontFromFileTTF() will return the ImFont* so you can store it if you need to select the font among multiple.
        // - If the file cannot be loaded, the function will return a nullptr. Please handle those errors in your application (e.g. use an assertion, or display an error and quit).
        // - The fonts will be rasterized at a given size (w/ oversampling) and stored into a texture when calling ImFontAtlas::Build()/GetTexDataAsXXXX(), which ImGui_ImplXXXX_NewFrame below will call.
        // - Use '#define IMGUI_ENABLE_FREETYPE' in your imconfig file to use Freetype for higher quality font rendering.
        // - Read 'docs/FONTS.md' for more instructions and details.
        // - Remember that in C/C++ if you want to include a backslash \ in a string literal you need to write a double backslash \\ !
        //io.Fonts->AddFontDefault();
        //io.Fonts->AddFontFromFileTTF("c:\\Windows\\Fonts\\segoeui.ttf", 18.0f);
        //io.Fonts->AddFontFromFileTTF("../../misc/fonts/DroidSans.ttf", 16.0f);
        //io.Fonts->AddFontFromFileTTF("../../misc/fonts/Roboto-Medium.ttf", 16.0f);
        //io.Fonts->AddFontFromFileTTF("../../misc/fonts/Cousine-Regular.ttf", 15.0f);
        //ImFont* font = io.Fonts->AddFontFromFileTTF("c:\\Windows\\Fonts\\ArialUni.ttf", 18.0f, nullptr, io.Fonts->GetGlyphRangesJapanese());
        //IM_ASSERT(font != nullptr);

        // Our state
        var show_demo_window = true;
        var show_another_window = false;
        // black background
        var clear_color: imguiz.ImVec4 = .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 1.0 };

        var f: f32 = 0.0;
        var counter: i32 = 0;

        // Main loop
        var done = false;
        while (!done) {
            // Poll and handle events (inputs, window resize, etc.)
            // You can read the io.WantCaptureMouse, io.WantCaptureKeyboard flags to tell if dear imgui wants to use your inputs.
            // - When io.WantCaptureMouse is true, do not dispatch mouse input data to your main application, or clear/overwrite your copy of the mouse data.
            // - When io.WantCaptureKeyboard is true, do not dispatch keyboard input data to your main application, or clear/overwrite your copy of the keyboard data.
            // Generally you may always pass all inputs to dear imgui, and hide them from your application based on those two flags.
            var event: imguiz.SDL_Event = undefined;
            while (imguiz.SDL_PollEvent(&event)) {
                _ = imguiz.cImGui_ImplSDL3_ProcessEvent(&event);
                if (event.type == imguiz.SDL_EVENT_QUIT)
                    done = true;
                if (event.type == imguiz.SDL_EVENT_WINDOW_CLOSE_REQUESTED and event.window.windowID == imguiz.SDL_GetWindowID(self.window.?))
                    done = true;
            }
            if ((imguiz.SDL_GetWindowFlags(self.window.?) & imguiz.SDL_WINDOW_MINIMIZED) > 0) {
                imguiz.SDL_Delay(10);
                continue;
            }

            // Resize swap chain?
            var fb_width: i32 = undefined;
            var fb_height: i32 = undefined;
            if (!imguiz.SDL_GetWindowSize(self.window.?, &fb_width, &fb_height)) return error.SDL_GetWindowSizeFailure;
            if (fb_width > 0 and fb_height > 0 and (self.swapchain_rebuild or self.vulkan_window.Width != fb_width or self.vulkan_window.Height != fb_height)) {
                imguiz.cImGui_ImplVulkan_SetMinImageCount(MIN_IMAGE_COUNT);
                imguiz.cImGui_ImplVulkanH_CreateOrResizeWindow(
                    self.vkInstance(),
                    self.vkPhysicalDevice(),
                    self.vkDevice(),
                    &self.vulkan_window,
                    self.vulkan.graphics_queue.family,
                    null,
                    fb_width,
                    fb_height,
                    MIN_IMAGE_COUNT,
                );
                self.vulkan_window.FrameIndex = 0;
                self.swapchain_rebuild = false;
            }

            // Start the Dear ImGui frame
            imguiz.cImGui_ImplVulkan_NewFrame();
            imguiz.cImGui_ImplSDL3_NewFrame();
            imguiz.ImGui_NewFrame();

            // 1. Show the big demo window (Most of the sample code is in ImGui::ShowDemoWindow()! You can browse its code to learn more about Dear ImGui!).
            if (show_demo_window) {
                imguiz.ImGui_ShowDemoWindow(&show_demo_window);
            }

            {
                _ = imguiz.ImGui_Begin("Hello, world!", null, 0);
                defer imguiz.ImGui_End();

                if (imguiz.ImGui_SmallButton("small button")) {
                    std.debug.print("small button clicked!!\n", .{});
                }

                imguiz.ImGui_Text("This is some useful text.");
                _ = imguiz.ImGui_Checkbox("Demo Window", &show_demo_window);
                _ = imguiz.ImGui_Checkbox("Another Window", &show_another_window);

                _ = imguiz.ImGui_SliderFloat("float", &f, 0.0, 1.0);
                _ = imguiz.ImGui_ColorEdit3("clear color", @ptrCast(&clear_color), 0);

                if (imguiz.ImGui_Button("Button")) counter += 1;
                imguiz.ImGui_SameLine();
                imguiz.ImGui_Text("counter = %d", counter);

                imguiz.ImGui_Text("Application average %.3f ms/frame (%.1f FPS)", 1000.0 / io.*.Framerate, io.*.Framerate);
            }

            // 3. Show another simple window.
            if (show_another_window) {
                _ = imguiz.ImGui_Begin("Another Window", &show_another_window, 0);
                defer imguiz.ImGui_End();
                imguiz.ImGui_Text("Hello from another window!");
                if (imguiz.ImGui_Button("Close Me")) show_another_window = false;
            }

            // Rendering
            imguiz.ImGui_Render();
            const draw_data = imguiz.ImGui_GetDrawData();
            const is_minimized = (draw_data.*.DisplaySize.x <= 0.0 or draw_data.*.DisplaySize.y <= 0.0);
            self.vulkan_window.ClearValue.color.float32[0] = clear_color.x * clear_color.w;
            self.vulkan_window.ClearValue.color.float32[1] = clear_color.y * clear_color.w;
            self.vulkan_window.ClearValue.color.float32[2] = clear_color.z * clear_color.w;
            self.vulkan_window.ClearValue.color.float32[3] = clear_color.w;
            if (!is_minimized) {
                try self.frameRender(draw_data);
            }

            if (io.*.ConfigFlags & imguiz.ImGuiConfigFlags_ViewportsEnable > 0) {
                imguiz.ImGui_UpdatePlatformWindows();
                imguiz.ImGui_RenderPlatformWindowsDefault();
            }

            if (!is_minimized) {
                try self.framePresent();
            }
        }

        // Cleanup
        try self.vulkan.device.deviceWaitIdle();
    }

    fn frameRender(self: *Self, draw_data: *imguiz.ImDrawData) !void {
        var wd = &self.vulkan_window;

        var image_acquired_semaphore = wd.FrameSemaphores.Data[wd.SemaphoreIndex].ImageAcquiredSemaphore;
        var render_complete_semaphore = wd.FrameSemaphores.Data[wd.SemaphoreIndex].RenderCompleteSemaphore;
        const result = (self.vulkan.device.acquireNextImageKHR(
            @enumFromInt(@intFromPtr(wd.Swapchain)),
            std.math.maxInt(u64),
            @enumFromInt(@intFromPtr(image_acquired_semaphore)),
            .null_handle,
        ) catch |err| {
            switch (err) {
                error.OutOfDateKHR => {
                    self.swapchain_rebuild = true;
                    return;
                },
                else => return err,
            }
        });

        if (result.result == .suboptimal_khr) {
            self.swapchain_rebuild = true;
        }

        wd.FrameIndex = result.image_index;

        var fd = &wd.Frames.Data[wd.FrameIndex];

        {
            const err = try self.vulkan.device.waitForFences(1, @ptrCast(&fd.Fence), imguiz.VK_TRUE, std.math.maxInt(u64));
            check_vk_result(@intFromEnum(err));
            try self.vulkan.device.resetFences(1, @ptrCast(&fd.Fence));
        }

        {
            try self.vulkan.device.resetCommandPool(@enumFromInt(@intFromPtr(fd.CommandPool)), .{});
            const info = vk.CommandBufferBeginInfo{
                .flags = .{ .one_time_submit_bit = true },
            };
            try self.vulkan.device.beginCommandBuffer(@enumFromInt(@intFromPtr(fd.CommandBuffer)), @ptrCast(&info));
        }
        {
            const info = vk.RenderPassBeginInfo{
                .render_pass = @enumFromInt(@intFromPtr(wd.RenderPass)),
                .framebuffer = @enumFromInt(@intFromPtr(fd.Framebuffer)),
                .render_area = .{ .extent = .{ .width = @intCast(wd.Width), .height = @intCast(wd.Height) }, .offset = .{ .x = 0, .y = 0 } },
                .clear_value_count = 1,
                .p_clear_values = @ptrCast(&wd.ClearValue),
            };
            self.vulkan.device.cmdBeginRenderPass(@enumFromInt(@intFromPtr(fd.CommandBuffer)), @ptrCast(&info), .@"inline");
        }

        // Record dear imgui primitives into command buffer
        imguiz.cImGui_ImplVulkan_RenderDrawData(draw_data, fd.CommandBuffer);

        // Submit command buffer
        self.vulkan.device.cmdEndRenderPass(@enumFromInt(@intFromPtr(fd.CommandBuffer)));
        {
            var wait_stage = vk.PipelineStageFlags{ .color_attachment_output_bit = true };
            const info = vk.SubmitInfo{
                .wait_semaphore_count = 1,
                .p_wait_semaphores = @ptrCast(&image_acquired_semaphore),
                .p_wait_dst_stage_mask = @ptrCast(&wait_stage),
                .command_buffer_count = 1,
                .p_command_buffers = @ptrCast(&fd.CommandBuffer),
                .signal_semaphore_count = 1,
                .p_signal_semaphores = @ptrCast(&render_complete_semaphore),
            };

            try self.vulkan.device.endCommandBuffer(@enumFromInt(@intFromPtr(fd.CommandBuffer)));
            self.vulkan.graphics_queue.mutex.lock();
            defer self.vulkan.graphics_queue.mutex.unlock();
            try self.vulkan.device.queueSubmit(
                self.vulkan.graphics_queue.handle,
                1,
                @ptrCast(&info),
                @enumFromInt(@intFromPtr(fd.Fence)),
            );
        }
    }

    fn framePresent(self: *Self) !void {
        var wd = &self.vulkan_window;
        if (self.swapchain_rebuild) {
            return;
        }
        var render_complete_semaphore = wd.FrameSemaphores.Data[wd.SemaphoreIndex].RenderCompleteSemaphore;
        const info = vk.PresentInfoKHR{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&render_complete_semaphore),
            .swapchain_count = 1,
            .p_swapchains = @ptrCast(&wd.Swapchain),
            .p_image_indices = @ptrCast(&wd.FrameIndex),
        };
        self.vulkan.graphics_queue.mutex.lock();
        defer self.vulkan.graphics_queue.mutex.unlock();
        _ = self.vulkan.device.queuePresentKHR(self.vulkan.graphics_queue.handle, @ptrCast(&info)) catch |err| {
            switch (err) {
                error.OutOfDateKHR => {
                    self.swapchain_rebuild = true;
                    return;
                },
                else => return err,
            }
        };

        wd.SemaphoreIndex = (wd.SemaphoreIndex + 1) % wd.SemaphoreCount; // Now we can use the next set of semaphores
    }

    fn setupVulkanWindow(self: *Self) !void {
        self.vulkan_window = .{
            .Surface = self.surface.?,
            .ClearEnable = true,
        };

        // Check for WSI support
        _ = self.vulkan.instance.getPhysicalDeviceSurfaceSupportKHR(
            self.vulkan.physical_device,
            self.vulkan.graphics_queue.family,
            @enumFromInt(@intFromPtr(self.vulkan_window.Surface)),
        ) catch return error.NoWSISupport;

        // Select Surface Format
        const requestSurfaceImageFormat = [_]imguiz.VkFormat{ imguiz.VK_FORMAT_B8G8R8A8_UNORM, imguiz.VK_FORMAT_R8G8B8A8_UNORM, imguiz.VK_FORMAT_B8G8R8_UNORM, imguiz.VK_FORMAT_R8G8B8_UNORM };
        const requestSurfaceColorSpace = imguiz.VK_COLORSPACE_SRGB_NONLINEAR_KHR;
        self.vulkan_window.SurfaceFormat = imguiz.cImGui_ImplVulkanH_SelectSurfaceFormat(
            self.vkPhysicalDevice(),
            self.vulkan_window.Surface,
            @ptrCast(&requestSurfaceImageFormat),
            requestSurfaceImageFormat.len,
            requestSurfaceColorSpace,
        );

        // Select Present Mode
        const present_modes = [_]imguiz.VkPresentModeKHR{
            // NOTE: uncommand for unlimited frame rate
            // c.VK_PRESENT_MODE_MAILBOX_KHR,
            // c.VK_PRESENT_MODE_IMMEDIATE_KHR,
            imguiz.VK_PRESENT_MODE_FIFO_KHR,
        };
        self.vulkan_window.PresentMode = imguiz.cImGui_ImplVulkanH_SelectPresentMode(
            self.vkPhysicalDevice(),
            self.vulkan_window.Surface,
            &present_modes[0],
            present_modes.len,
        );

        // Create SwapChain, RenderPass, Framebuffer, etc.
        imguiz.cImGui_ImplVulkanH_CreateOrResizeWindow(
            self.vkInstance(),
            self.vkPhysicalDevice(),
            self.vkDevice(),
            &self.vulkan_window,
            self.vulkan.graphics_queue.family,
            null,
            WIDTH,
            HEIGHT,
            MIN_IMAGE_COUNT,
        );
    }

    fn loader(name: [*c]const u8, instance: ?*anyopaque) callconv(.c) ?*const fn () callconv(.c) void {
        const vkGetInstanceProcAddr: imguiz.PFN_vkGetInstanceProcAddr = @ptrCast(imguiz.SDL_Vulkan_GetVkGetInstanceProcAddr());
        return vkGetInstanceProcAddr.?(@ptrCast(instance), name);
    }

    fn check_vk_result(err: imguiz.VkResult) callconv(.c) void {
        if (err == 0) return;
        std.debug.print("[vulkan] Error: VkResult = {d}\n", .{err});
        if (err < 0) std.process.exit(1);
    }

    fn vkInstance(self: *const Self) imguiz.VkInstance {
        return @ptrFromInt(@intFromEnum(self.vulkan.instance.handle));
    }

    fn vkDevice(self: *const Self) imguiz.VkDevice {
        return @ptrFromInt(@intFromEnum(self.vulkan.device.handle));
    }

    fn vkPhysicalDevice(self: *const Self) imguiz.VkPhysicalDevice {
        return @ptrFromInt(@intFromEnum(self.vulkan.physical_device));
    }

    fn vkDescriptorPool(self: *const Self) imguiz.VkDescriptorPool {
        return @ptrFromInt(@intFromEnum(self.vulkan.descriptor_pool));
    }

    fn vkQueue(self: *const Self) imguiz.VkQueue {
        return @ptrFromInt(@intFromEnum(self.vulkan.graphics_queue.handle));
    }

    pub fn deinit(self: *const Self) void {
        imguiz.cImGui_ImplVulkan_Shutdown();
        imguiz.cImGui_ImplSDL3_Shutdown();

        // if (self.vulkan_window) |*vulkan_window| {
        imguiz.cImGui_ImplVulkanH_DestroyWindow(
            self.vkInstance(),
            self.vkDevice(),
            @constCast(@ptrCast(&self.vulkan_window)),
            null,
        );
        // }

        if (self.window) |window| {
            imguiz.SDL_DestroyWindow(window);
        }
        imguiz.SDL_Quit();

        self.allocator.destroy(self);
    }
};
