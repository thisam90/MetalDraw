#include "metaldraw.h"

int main(void)
{
    InitWindow(800, 600, "MetalDraw Window");

    while (!WindowShouldClose())
    {
        @autoreleasepool
        {
            BeginDrawing();
            ClearBackground((Color){ 0, 128, 255, 255 });   
            EndDrawing();
        }
    }

    CloseWindow();
    return 0;
}