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

// Window creation descriptor (Apple/Metal style: fill a typed descriptor, pass it to the
// initializer). Get a defaults-populated one from GetWindowConfigDefault() and override fields.
typedef struct WindowConfig {
    bool resizable;     // window can be resized (default true)
    bool undecorated;   // borderless: no title bar / buttons
    bool hidden;        // create off-screen; show later with no flash
    bool topmost;       // floating window level (always on top)
    bool fullscreen;    // start in native macOS fullscreen (ignored if 'hidden' is set)
} WindowConfig;

WindowConfig GetWindowConfigDefault(void);   // defaults-populated descriptor to override
void InitWindow(int width, int height, const char *title);   // window with the default config
void InitWindowEx(int width, int height, const char *title, WindowConfig config);
bool WindowShouldClose(void);
void CloseWindow(void);
bool IsWindowReady(void);

void SetWindowTitle(const char *title);
void MinimizeWindow(void);
void MaximizeWindow(void);
void RestoreWindow(void);

void SetWindowSize(int width, int height);
void SetWindowResizable(bool resizable);
void SetWindowPosition(int x, int y);   // content top-left, top-left origin (primary display)
void SetWindowMinSize(int width, int height);   // min CONTENT size (user-resize limit)
void SetWindowMaxSize(int width, int height);   // max CONTENT size (user-resize limit)
void SetWindowOpacity(float opacity);   // 0.0 = transparent .. 1.0 = opaque (whole window)
void SetWindowFocused(void);            // bring to front + give input focus
void HideWindow(void);                  // orderOut: — off screen (IsWindowHidden true)
void UnhideWindow(void);                // orderFront: — put it back on screen
void SetWindowTopmost(bool enabled);    // always-on-top (floating window level)
void ToggleFullscreen(void);            // native macOS fullscreen (own Space; async)

bool IsWindowMinimized(void);   // Dock-miniaturized
bool IsWindowMaximized(void);   // zoomed (frame fills the standard maximize)
bool IsWindowFocused(void);     // has keyboard/input focus (key window)
bool IsWindowHidden(void);      // orderOut:'d — NOT the same as minimized
bool IsWindowFullscreen(void);  // in native macOS fullscreen (own Space)

bool IsWindowResized(void);

int GetScreenWidth(void);    // logical size in POINTS
int GetScreenHeight(void);

int GetRenderWidth(void);    // physical size in PIXELS
int GetRenderHeight(void);

int GetWindowPositionX(void);   // content top-left X (points, top-left origin)
int GetWindowPositionY(void);   // content top-left Y (points, top-left origin)

float GetWindowScaleDPI(void);  // backing scale (1.0 = non-Retina, 2.0 = Retina)

// Monitors — indexed into the system screen list; sizes/positions in POINTS
int  GetMonitorCount(void);
int  GetCurrentMonitor(void);            // monitor the window is currently on
int  GetMonitorWidth(int monitor);
int  GetMonitorHeight(int monitor);
int  GetMonitorRefreshRate(int monitor); // Hz (120 on ProMotion)
int  GetMonitorPositionX(int monitor);   // top-left origin (primary display)
int  GetMonitorPositionY(int monitor);
const char *GetMonitorName(int monitor); // valid until the next GetMonitorName call
void SetWindowMonitor(int monitor);      // move the window to a monitor (centered)


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