#include "metaldraw.h"

int main(void)
{
    InitWindow(800, 600, "MetalDraw Window");
    TraceLog(MD_LOG_INFO, "screen size: %d x %d points", GetScreenWidth(), GetScreenHeight());
    TraceLog(MD_LOG_INFO, "render size: %d x %d pixels", GetRenderWidth(), GetRenderHeight());
    Color someColor = { 255, 0, 0, 255 };


while (!WindowShouldClose())
    {
        @autoreleasepool
        {
           if (IsWindowResized()) {
                TraceLog(MD_LOG_INFO, "window resized this frame");
           }

            BeginDrawing();
            ClearBackground(someColor);
            EndDrawing();
        }
    }

    CloseWindow();
    return 0;
}