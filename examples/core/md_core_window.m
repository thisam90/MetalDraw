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
         
    int frameCount = 0;

    while (!WindowShouldClose())
    {
        if (IsWindowResized()) {
            TraceLog(MD_LOG_INFO, "window resized this frame");
        }

        // Input test: click THIS window to focus it (not the terminal), then HOLD keys to change
        // the color — live visual feedback, no need to watch the terminal (and no text yet).
        Color bg = (Color){ 30, 30, 40, 255 };                          // idle: dark
        if (IsKeyDown(MD_KEY_SPACE)) bg = (Color){ 40, 120, 255, 255 };  // SPACE -> blue
        if (IsKeyDown(MD_KEY_W))     bg = (Color){ 60, 200, 90, 255 };   // W     -> green
        if (IsKeyDown(MD_KEY_A))     bg = (Color){ 230, 190, 40, 255 };  // A     -> yellow
        if (IsKeyDown(MD_KEY_S))     bg = (Color){ 220, 70, 70, 255 };   // S     -> red
        if (IsKeyDown(MD_KEY_D))     bg = (Color){ 180, 80, 220, 255 };  // D     -> purple
        if (IsKeyDown(MD_KEY_LEFT) || IsKeyDown(MD_KEY_RIGHT) ||
            IsKeyDown(MD_KEY_UP)   || IsKeyDown(MD_KEY_DOWN))
            bg = (Color){ 255, 255, 255, 255 };                          // any arrow -> white
        if (IsKeyDown(MD_KEY_LEFT_SHIFT) || IsKeyDown(MD_KEY_RIGHT_SHIFT))
            bg = (Color){ 40, 220, 220, 255 };                           // SHIFT -> cyan (modifier / flagsChanged)
        if (IsKeyDown(MD_KEY_ENTER)) bg = (Color){ 255, 140, 0, 255 };   // ENTER -> orange

        BeginDrawing();
        ClearBackground(bg);
        EndDrawing();
        if (++frameCount % 60 == 0) {
            float ft = GetFrameTime();
            TraceLog(MD_LOG_INFO, "t=%.2fs  frametime=%.4fs  raw=%.0f fps  GetFPS=%d",
                     GetTime(), ft, ft > 0.0f ? 1.0 / ft : 0.0, GetFPS());
        }
    }

    CloseWindow();
    return 0;
}