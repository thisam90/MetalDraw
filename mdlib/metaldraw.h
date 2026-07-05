#ifndef METALDRAW_H
#define METALDRAW_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct Color {
    unsigned char r;
    unsigned char g;
    unsigned char b;
    unsigned char a;
} Color;

void InitWindow(int width, int height, const char *title);
bool WindowShouldClose(void);
void CloseWindow(void);

void BeginDrawing(void);
void ClearBackground(Color color);
void EndDrawing(void);

#ifdef __cplusplus
}
#endif

#endif // METALDRAW_H