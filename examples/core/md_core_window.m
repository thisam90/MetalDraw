#include "metaldraw.h"

int main(void)
{
    InitWindow(800, 600, "MetalDraw Window");
    SetTraceLogLevel(MD_LOG_ERROR);

    Color someColor = { 255, 0, 0, 255 };


    while (!WindowShouldClose())
    {
        @autoreleasepool
        {
            BeginDrawing();
            ClearBackground(someColor);
            EndDrawing();
        }
    }

    CloseWindow();
    return 0;
}