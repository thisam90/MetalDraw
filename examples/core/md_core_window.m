#include "metaldraw.h"

int main(void)
{
    InitWindow(800, 600, "MetalDraw Window");
        SetTargetFPS(0);
    TraceLog(MD_LOG_INFO, "screen size: %d x %d points", GetScreenWidth(), GetScreenHeight());
    TraceLog(MD_LOG_INFO, "render size: %d x %d pixels", GetRenderWidth(), GetRenderHeight());
    SetWindowSize(1024, 768);
    SetWindowResizable(true);
    TraceLog(MD_LOG_INFO, "after SetWindowSize: %d x %d points, %d x %d pixels",GetScreenWidth(), GetScreenHeight(), GetRenderWidth(), GetRenderHeight());
         
    Color someColor = { 255, 0, 0, 255 };

    int frameCount = 0;
    double before = GetTime();

    TraceLog(MD_LOG_INFO, "WaitTime(0.5) waited %.4fs", GetTime() - before);

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
            if (++frameCount % 60 == 0)
            {
                TraceLog(MD_LOG_INFO, "t=%.2fs  frametime=%.4fs  (~%.0f fps)",
                GetTime(), GetFrameTime(), 1.0 / GetFrameTime());
            }
             if (++frameCount % 60 == 0) {
                TraceLog(MD_LOG_INFO, "t=%.2fs  raw=%.0f fps  GetFPS=%d",
                GetTime(), 1.0 / GetFrameTime(), GetFPS());
            }
        }
    }

    CloseWindow();
    return 0;
}