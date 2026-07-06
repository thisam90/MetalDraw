#include "metaldraw.h"

int main(void)
{
    InitWindow(800, 600, "MetalDraw Window");
        if (!IsWindowReady()) { CloseWindow(); return 1; }
        SetTargetFPS(0);
    TraceLog(MD_LOG_INFO, "screen size: %d x %d points", GetScreenWidth(), GetScreenHeight());
    TraceLog(MD_LOG_INFO, "render size: %d x %d pixels", GetRenderWidth(), GetRenderHeight());
    SetWindowSize(1024, 768);
    SetWindowResizable(true);
    TraceLog(MD_LOG_INFO, "after SetWindowSize: %d x %d points, %d x %d pixels",GetScreenWidth(), GetScreenHeight(), GetRenderWidth(), GetRenderHeight());
         
    Color someColor = { 255, 0, 0, 255 };

    int frameCount = 0;

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
            if (++frameCount % 60 == 0) {
                float ft = GetFrameTime();
                TraceLog(MD_LOG_INFO, "t=%.2fs  frametime=%.4fs  raw=%.0f fps  GetFPS=%d",
                         GetTime(), ft, ft > 0.0f ? 1.0 / ft : 0.0, GetFPS());
            }
        }
    }

    CloseWindow();
    return 0;
}