#ifdef __MINGW32__
#undef _FORTIFY_SOURCE
#define _FORTIFY_SOURCE 0

#define __INTRIN_H_ 1
void __debugbreak(void);
#endif

#define IMGUI_USE_WCHAR32 1

#include <SDL3/SDL.h>
#include <SDL3/SDL_vulkan.h>
#include <dcimgui.h>
#include <dcimgui_impl_sdl3.h>
#include <dcimgui_impl_vulkan.h>
