#ifndef METALDRAW_H
#define METALDRAW_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    MD_LOG_ALL = 0,
    MD_LOG_TRACE,
    MD_LOG_DEBUG,
    MD_LOG_INFO,
    MD_LOG_WARNING,
    MD_LOG_ERROR,
    MD_LOG_FATAL,
    MD_LOG_NONE
} TraceLogLevel;

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

void TraceLog(int logLevel, const char *text, ...);
void SetTraceLogLevel(int logLevel);

#ifdef __cplusplus
}
#endif

#endif // METALDRAW_H