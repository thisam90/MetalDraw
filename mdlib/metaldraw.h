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

// Keyboard keys — values match raylib's KeyboardKey (familiarity); mapped internally from the
// physical, layout-independent macOS keyCode. (Subset for now — grows as we add keys.)
typedef enum {
    MD_KEY_NULL          = 0,
    // Printable
    MD_KEY_APOSTROPHE    = 39,
    MD_KEY_COMMA         = 44,
    MD_KEY_MINUS         = 45,
    MD_KEY_PERIOD        = 46,
    MD_KEY_SLASH         = 47,
    MD_KEY_ZERO          = 48, MD_KEY_ONE, MD_KEY_TWO, MD_KEY_THREE, MD_KEY_FOUR,
    MD_KEY_FIVE, MD_KEY_SIX, MD_KEY_SEVEN, MD_KEY_EIGHT, MD_KEY_NINE,       // 48..57
    MD_KEY_SEMICOLON     = 59,
    MD_KEY_EQUAL         = 61,
    MD_KEY_A             = 65, MD_KEY_B, MD_KEY_C, MD_KEY_D, MD_KEY_E, MD_KEY_F, MD_KEY_G,
    MD_KEY_H, MD_KEY_I, MD_KEY_J, MD_KEY_K, MD_KEY_L, MD_KEY_M, MD_KEY_N, MD_KEY_O,
    MD_KEY_P, MD_KEY_Q, MD_KEY_R, MD_KEY_S, MD_KEY_T, MD_KEY_U, MD_KEY_V, MD_KEY_W,
    MD_KEY_X, MD_KEY_Y, MD_KEY_Z,                                           // 65..90
    MD_KEY_LEFT_BRACKET  = 91,
    MD_KEY_BACKSLASH     = 92,
    MD_KEY_RIGHT_BRACKET = 93,
    MD_KEY_GRAVE         = 96,
    // Function / navigation
    MD_KEY_SPACE         = 32,
    MD_KEY_ESCAPE        = 256,
    MD_KEY_ENTER         = 257,
    MD_KEY_TAB           = 258,
    MD_KEY_BACKSPACE     = 259,
    MD_KEY_INSERT        = 260,   // no Mac keycode
    MD_KEY_DELETE        = 261,   // forward-delete
    MD_KEY_RIGHT         = 262,
    MD_KEY_LEFT          = 263,
    MD_KEY_DOWN          = 264,
    MD_KEY_UP            = 265,
    MD_KEY_PAGE_UP       = 266,
    MD_KEY_PAGE_DOWN     = 267,
    MD_KEY_HOME          = 268,
    MD_KEY_END           = 269,
    MD_KEY_CAPS_LOCK     = 280,   // reports the caps LATCH (LED on/off), not a momentary press
    MD_KEY_SCROLL_LOCK   = 281,   // no Mac keycode
    MD_KEY_NUM_LOCK      = 282,   // no Mac keycode
    MD_KEY_PRINT_SCREEN  = 283,   // no Mac keycode
    MD_KEY_PAUSE         = 284,   // no Mac keycode
    MD_KEY_F1            = 290, MD_KEY_F2, MD_KEY_F3, MD_KEY_F4, MD_KEY_F5, MD_KEY_F6,
    MD_KEY_F7, MD_KEY_F8, MD_KEY_F9, MD_KEY_F10, MD_KEY_F11, MD_KEY_F12,    // 290..301
    // Keypad
    MD_KEY_KP_0          = 320, MD_KEY_KP_1, MD_KEY_KP_2, MD_KEY_KP_3, MD_KEY_KP_4,
    MD_KEY_KP_5, MD_KEY_KP_6, MD_KEY_KP_7, MD_KEY_KP_8, MD_KEY_KP_9,        // 320..329
    MD_KEY_KP_DECIMAL    = 330,
    MD_KEY_KP_DIVIDE     = 331,
    MD_KEY_KP_MULTIPLY   = 332,
    MD_KEY_KP_SUBTRACT   = 333,
    MD_KEY_KP_ADD        = 334,
    MD_KEY_KP_ENTER      = 335,
    MD_KEY_KP_EQUAL      = 336,
    // Modifiers (arrive via flagsChanged, not keyDown/keyUp)
    MD_KEY_LEFT_SHIFT    = 340,
    MD_KEY_LEFT_CONTROL  = 341,
    MD_KEY_LEFT_ALT      = 342,
    MD_KEY_LEFT_SUPER    = 343,   // left Command (⌘)
    MD_KEY_RIGHT_SHIFT   = 344,
    MD_KEY_RIGHT_CONTROL = 345,
    MD_KEY_RIGHT_ALT     = 346,
    MD_KEY_RIGHT_SUPER   = 347,   // right Command (⌘)
    MD_KEY_KB_MENU       = 348    // no Mac keycode
} KeyboardKey;

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

// Input: Keyboard — key is an MD_KEY_* value
bool IsKeyPressed(int key);    // went down THIS frame (edge)
bool IsKeyDown(int key);       // currently held
bool IsKeyReleased(int key);   // went up THIS frame (edge)
bool IsKeyUp(int key);         // currently not held

void TraceLog(int logLevel, const char *text, ...);
void SetTraceLogLevel(int logLevel);

#ifdef __cplusplus
}
#endif

#endif // METALDRAW_H