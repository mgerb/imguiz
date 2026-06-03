pub const imguiz = @cImport({
    @cDefine("IMGUI_USE_WCHAR32", "1");
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_vulkan.h");
    @cInclude("dcimgui.h");
    @cInclude("dcimgui_impl_sdl3.h");
    @cInclude("dcimgui_impl_vulkan.h");
    // ...add other includes here if needed
});
