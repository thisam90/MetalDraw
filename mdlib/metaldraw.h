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
bool IsWindowReady(void);

void SetWindowTitle(const char *title);
void MinimizeWindow(void);
void MaximizeWindow(void);
void RestoreWindow(void);

void SetWindowSize(int width, int height);
void SetWindowResizable(bool resizable);

bool IsWindowResized(void);

int GetScreenWidth(void);    // logical size in POINTS
int GetScreenHeight(void);

int GetRenderWidth(void);    // physical size in PIXELS
int GetRenderHeight(void);


double GetTime(void);        // seconds since InitWindow (monotonic)
float  GetFrameTime(void);    // last frame delta, seconds


int  GetFPS(void);            // smoothed frames-per-second
void WaitTime(double seconds);   // block for a duration (monotonic clock)
void SetTargetFPS(int fps);   // cap frame rate (0 = uncapped)

void BeginDrawing(void);
void ClearBackground(Color color);
void EndDrawing(void);

void TraceLog(int logLevel, const char *text, ...);
void SetTraceLogLevel(int logLevel);

#ifdef __cplusplus
}
#endif

#endif // METALDRAW_H