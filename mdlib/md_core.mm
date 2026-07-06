#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

#include "metaldraw.h"
#include <mach/mach_time.h>   // mach_wait_until / mach_timebase_info

@interface MDWindowDelegate : NSObject <NSWindowDelegate>
@end

// NSWindow subclass used for ALL windows. Its only job: force canBecomeKey/Main = YES so a
// BORDERLESS (undecorated) window can still receive keyboard focus — borderless NSWindows return
// NO by default. Harmless for a titled window (which already returns YES).
@interface MDWindow : NSWindow
@end


//MARK: - Global state (private to this file)
static bool gInitFailed = false;   // true if InitWindow failed (e.g. no Metal device)
static bool gShouldClose = false;
static bool gWindowResized = false;
static NSWindow *gWindow = nil;
static id<MTLDevice> gDevice = nil;
static id<MTLCommandQueue> gCommandQueue = nil;
static CAMetalLayer *gMetalLayer = nil;
static MDWindowDelegate *gWindowDelegate = nil;
static id<CAMetalDrawable> gDrawable = nil;
static id<MTLCommandBuffer> gCommandBuffer = nil;

static double gStartTime     = 0.0;
static double gPrevFrameTime = 0.0;
static float  gFrameTime     = 0.0f;
static float  gFrameTimeAvg  = 0.0f;
static double gTargetFPS = 0.0;    // 0 = uncapped; else target frames/sec

//MARK: - Internal helpers (private — not in the public header)

// Forward declaration so the delegate (defined below, but above InitWindow)
// can call this. 'static' = private to this file.
static void md_UpdateDrawableSize(void);


@implementation MDWindowDelegate

- (BOOL)windowShouldClose:(NSWindow *)sender {
    gShouldClose = true;
    return NO;
}

- (void)requestQuit:(id)sender {
    gShouldClose = true;   // Cmd-Q → same clean shutdown path as the red close button
}

- (void)windowDidResize:(NSNotification *)notification {
    gWindowResized = true;
    md_UpdateDrawableSize();
}

- (void)windowDidChangeBackingProperties:(NSNotification *)notification {
    if (gWindow == nil || gMetalLayer == nil) return;
    // Fires when the window moves to a display of different scale (Retina <-> 1x) or
    // color space — windowDidResize: does NOT fire on a pure scale change. We host the
    // layer (assigned it ourselves), so AppKit won't auto-update contentsScale for us;
    // re-sync it to the NEW backing scale (convertSizeToBacking: inside the helper reads it).
    gMetalLayer.contentsScale = gWindow.backingScaleFactor;
    md_UpdateDrawableSize();
}

@end


@implementation MDWindow
- (BOOL)canBecomeKeyWindow  { return YES; }   // borderless windows return NO by default
- (BOOL)canBecomeMainWindow { return YES; }
@end


// Content-view size in backing PIXELS via AppKit's designated points->pixels
// conversion (Apple's guidance: use this, not a manual * backingScaleFactor).
// Shared by the drawable sizing and GetRenderWidth/Height so the drawable we
// render into and the size we report are computed identically and can't drift.
// Caller ensures gWindow != nil.
static NSSize md_ContentPixelSize(void)
{
    NSView *view = gWindow.contentView;
    return [view convertSizeToBacking:view.bounds.size];
}

static void md_UpdateDrawableSize(void)
{
    if (gWindow == nil || gMetalLayer == nil) return;
    NSSize px = md_ContentPixelSize();
    if (px.width  < 1) px.width  = 1;   // a 0-dimension drawableSize is invalid (nextDrawable fails)
    if (px.height < 1) px.height = 1;
    gMetalLayer.drawableSize = px;
}

// Minimal main menu so the app has a menu bar and a working Cmd-Q. Key equivalents
// dispatch through the key window then NSApp.mainMenu during [NSApp sendEvent:], which
// our own event pump already calls — so setting the menu is all it takes. Quit sets
// gShouldClose (like the red button) so both quits share one clean teardown via the loop.
static void md_SetupMenuBar(void)
{
    NSMenu *mainMenu = [[NSMenu alloc] init];

    // First submenu = the "application menu" (the system labels it with the app name).
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:appMenuItem];

    NSMenu *appMenu = [[NSMenu alloc] init];
    appMenuItem.submenu = appMenu;

    NSString *appName   = [[NSProcessInfo processInfo] processName];
    NSString *quitTitle = [@"Quit " stringByAppendingString:appName];
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:quitTitle
                                                      action:@selector(requestQuit:)
                                               keyEquivalent:@"q"];   // @"q" + default ⌘ = Cmd-Q
    quitItem.target = gWindowDelegate;   // route Quit/Cmd-Q through our own shutdown flag
    [appMenu addItem:quitItem];

    NSApp.mainMenu = mainMenu;   // strong ref keeps the whole tree alive (ARC)
}


//MARK: - Window: Lifecycle

WindowConfig GetWindowConfigDefault(void)
{
    // Metal-descriptor style: return a fully-populated descriptor with sensible defaults; the
    // caller flips only the fields it cares about, then hands it to InitWindowEx.
    WindowConfig cfg;
    cfg.resizable   = true;
    cfg.undecorated = false;
    cfg.hidden      = false;
    cfg.topmost     = false;
    cfg.fullscreen  = false;
    return cfg;
}

void InitWindow(int width, int height, const char *title)
{
    InitWindowEx(width, height, title, GetWindowConfigDefault());   // the descriptor path, defaulted
}

void InitWindowEx(int width, int height, const char *title, WindowConfig config)
{
    [NSApplication sharedApplication];
    if (gWindow != nil) CloseWindow();   // re-init: tear down any prior session cleanly first
    gInitFailed = false;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    NSRect frame = NSMakeRect(0, 0, width, height);
    // Undecorated => borderless (no title bar/buttons); otherwise the standard titled chrome.
    // Resizable is an independent styleMask bit layered on top of either base.
    NSWindowStyleMask style = config.undecorated
        ? NSWindowStyleMaskBorderless
        : (NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable);
    if (config.resizable) style |= NSWindowStyleMaskResizable;
    // MDWindow (NSWindow subclass) forces canBecomeKey/Main=YES so a BORDERLESS window can still
    // take keyboard focus (a plain borderless NSWindow returns NO); a no-op for a titled window.
    gWindow = [[MDWindow alloc] initWithContentRect:frame
                                          styleMask:style
                                            backing:NSBackingStoreBuffered
                                              defer:NO];

    // ARC is the sole owner of gWindow (strong global). A programmatically-created window
    // defaults to releasedWhenClosed=YES, so [gWindow close] in CloseWindow would send an
    // EXTRA release on top of ARC's -> over-release/UAF. Make ARC the only owner.
    gWindow.releasedWhenClosed = NO;

    [gWindow setTitle:[NSString stringWithUTF8String:(title ? title : "")]];   // NULL-safe
    [gWindow center];

    gWindowDelegate = [[MDWindowDelegate alloc] init];
    gWindow.delegate = gWindowDelegate;

    // FullScreenPrimary lets THIS window enter native full-screen (its own Space) via
    // toggleFullScreen: and shows the green full-screen button. (Auxiliary — the old value —
    // only lets a window ACCOMPANY another window's full-screen Space; it can't go full-screen
    // itself, so toggleFullScreen: would be a no-op.)
    gWindow.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;

    // Metal setup
    gDevice = MTLCreateSystemDefaultDevice();
      if (gDevice == nil) {
        TraceLog(MD_LOG_ERROR, "InitWindow: no Metal-capable GPU (MTLCreateSystemDefaultDevice returned nil)");
        gInitFailed = true;
        return;
    }
    gCommandQueue = [gDevice newCommandQueue];
        if (gCommandQueue == nil) {
        TraceLog(MD_LOG_ERROR, "InitWindow: failed to create Metal command queue");
        gInitFailed = true;
        return;
    }

    gMetalLayer = [CAMetalLayer layer];
    gMetalLayer.device = gDevice;

    // Color contract: BGRA8Unorm = PASSTHROUGH — bytes we write are the bytes shown
    // (byte-in = byte-shown), matching raylib's Color{0-255}. We deliberately do NOT use
    // the _sRGB format: it gamma-converts on write/read (correct for linear-space blending
    // and lighting) but needs colors authored in linear space, and half-switching would
    // double-gamma. Revisit _sRGB + Display-P3 as a coordinated pipeline change when
    // textures/blending land (M3+).
    gMetalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;

    // framebufferOnly = YES (the default, made explicit): the drawable is render-target-only
    // — cheapest fast path, but it blocks GPU readback. Flip to NO when TakeScreenshot /
    // texture readback lands.
    gMetalLayer.framebufferOnly = YES;

    NSView *contentView = gWindow.contentView;
    contentView.layer = gMetalLayer;
    contentView.wantsLayer = YES;

    gMetalLayer.contentsScale = gWindow.backingScaleFactor;
    md_UpdateDrawableSize();

    TraceLog(MD_LOG_INFO, "MetalDraw: GPU = %s", gDevice.name.UTF8String);

    md_SetupMenuBar();

    if (config.topmost) gWindow.level = NSFloatingWindowLevel;   // always-on-top from creation

    // hidden wins over fullscreen (fullscreen implies on-screen). Surface the dropped request
    // rather than silently ignoring it.
    if (config.hidden && config.fullscreen) {
        TraceLog(MD_LOG_WARNING, "InitWindowEx: fullscreen ignored because hidden is set");
    }

    // Show unless created hidden — 'hidden' lets the caller position/prepare before the first
    // paint with no flash (a freshly-alloc'd NSWindow is off-screen until ordered front). A
    // hidden window is never sent fullscreen (fullscreen implies on-screen).
    if (!config.hidden) {
        [gWindow makeKeyAndOrderFront:nil];
        [NSApp activate];   // macOS 14+ cooperative activation (replaces activateIgnoringOtherApps:)
        if (config.fullscreen) [gWindow toggleFullScreen:nil];   // native fullscreen (async)
    }


    // Monotonic clock start. CACurrentMediaTime() is mach_absolute_time in seconds
    // (pauses during system sleep — desirable, no post-wake delta spike).
    gStartTime = CACurrentMediaTime();
    gPrevFrameTime = 0.0;   // baseline is set at the FIRST EndDrawing, not from setup time
}

bool IsWindowReady(void)
{
    return !gInitFailed && gWindow != nil && gDevice != nil
        && gCommandQueue != nil && gMetalLayer != nil;
}



bool WindowShouldClose(void)
{
    // (gWindowResized is cleared at the END of the frame in EndDrawing, not here — so a
    //  resize is visible for the whole frame it happens in, incl. programmatic SetWindowSize.)

    // Drain events under a per-frame pool: nextEventMatchingMask/sendEvent autorelease
    // NSEvents; without a pool they'd accumulate (no [NSApp run] top-level pool here).
    @autoreleasepool {
        NSEvent *event;
        while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                           untilDate:[NSDate distantPast]
                                              inMode:NSDefaultRunLoopMode
                                             dequeue:YES]) != nil)
        {
            [NSApp sendEvent:event];
        }
    }
    return gShouldClose;
}

void CloseWindow(void)
{
    // Drain in-flight GPU work first: a late completion handler (GPU-error logging) must not
    // fire after teardown / process-exit and race stdout. Command buffers complete in order,
    // so waiting on a fresh one waits for all prior committed frames.
    if (gCommandQueue != nil) {
        id<MTLCommandBuffer> drain = [gCommandQueue commandBuffer];
        [drain commit];
        [drain waitUntilCompleted];
    }

    [gWindow close];

    // Null every global so a later InitWindow starts from a clean slate
    // (ARC releases each ObjC object as its last strong ref drops here).
    gWindow         = nil;
    gWindowDelegate = nil;
    gMetalLayer     = nil;
    gDrawable       = nil;
    gCommandBuffer  = nil;
    gCommandQueue   = nil;
    gDevice         = nil;
    NSApp.mainMenu  = nil;

    // Reset frame/loop state to defaults.
    gShouldClose   = false;
    gWindowResized = false;
    gInitFailed    = false;
    gStartTime     = 0.0;
    gPrevFrameTime = 0.0;
    gFrameTime     = 0.0f;
    gFrameTimeAvg  = 0.0f;
    gTargetFPS     = 0.0;
}


//MARK: - Window: Management

// Guard shared by the window-management setters: warns once if there's no window yet.
static bool md_RequireWindow(const char *fn)
{
    if (gWindow != nil) return true;
    TraceLog(MD_LOG_WARNING, "%s: no window (call InitWindow first)", fn);
    return false;
}

// Primary-display height in POINTS (re-read per call). CGDisplayBounds(CGMainDisplayID()) is
// the menu-bar display — origin (0,0), raylib's "primary" — so it survives display hot-plug /
// rearrangement with no cached-height staleness. Points, matching NSWindow.frame (not pixels).
static CGFloat md_PrimaryDisplayHeight(void)
{
    return CGDisplayBounds(CGMainDisplayID()).size.height;
}

void SetWindowTitle(const char *title)
{
    if (!md_RequireWindow("SetWindowTitle")) return;
    gWindow.title = [NSString stringWithUTF8String:(title ? title : "")];   // NULL-safe
}

void MinimizeWindow(void)
{
    if (!md_RequireWindow("MinimizeWindow")) return;
    [gWindow miniaturize:nil];
}

void MaximizeWindow(void)
{
    if (!md_RequireWindow("MaximizeWindow")) return;
    // zoom: is a TOGGLE; guard on isZoomed so repeated calls stay idempotent (raylib contract).
    if (!gWindow.zoomed) [gWindow zoom:nil];   // macOS "zoom" — nearest native maximize
}

void RestoreWindow(void)
{
    if (!md_RequireWindow("RestoreWindow")) return;
    // Reverse BOTH minimize and maximize (raylib's Restore contract): deminiaturize: only
    // un-minimizes; zoom: (toggle) un-maximizes when currently zoomed.
    if (gWindow.miniaturized) [gWindow deminiaturize:nil];
    if (gWindow.zoomed)       [gWindow zoom:nil];
}

void SetWindowSize(int width, int height)
{
    if (!md_RequireWindow("SetWindowSize")) return;
    // Sets the CONTENT area in points (the mirror of GetScreenWidth/Height). This
    // resizes the window's frame, which fires windowDidResize: -> our
    // md_UpdateDrawableSize() re-syncs the Metal drawable for us, no manual poke.
    [gWindow setContentSize:NSMakeSize(width, height)];
}

void SetWindowResizable(bool resizable)
{
    if (!md_RequireWindow("SetWindowResizable")) return;
    // Resizability IS a styleMask bit — no separate boolean exists in AppKit.
    // Flip only NSWindowStyleMaskResizable, leaving .titled (and the rest) intact:
    // removing .titled is the combo reported to misbehave on Tahoe; toggling just
    // .resizable on a titled window is the safe path.
    if (resizable) {
        gWindow.styleMask |= NSWindowStyleMaskResizable;
    } else {
        gWindow.styleMask &= ~NSWindowStyleMaskResizable;
    }
}

void SetWindowPosition(int x, int y)
{
    if (!md_RequireWindow("SetWindowPosition")) return;
    if (IsWindowFullscreen()) return;   // fullscreen owns its Space at the full frame — a move
                                        // here won't migrate it and corrupts the restore frame
                                        // (matches GLFW: setWindowPos is a no-op in fullscreen)
    // (x,y) = desired CONTENT top-left in raylib space (top-left origin, y DOWN). Rebuild the
    // content rect at the CURRENT content size, un-flip y to AppKit's bottom-left (content's
    // bottom edge), grow it back to a FRAME rect (re-adds the title bar for the current style),
    // and hand setFrameOrigin: the frame bottom-left it expects — feeding the content origin
    // straight in would be off by the title-bar height. Negative x/y are intentionally NOT
    // clamped (needed for displays left of / above the primary in a multi-monitor layout).
    NSRect content = [gWindow contentRectForFrameRect:gWindow.frame];   // current content size
    CGFloat bottomY = md_PrimaryDisplayHeight() - ((CGFloat)y + content.size.height);
    NSRect wantContent = NSMakeRect((CGFloat)x, bottomY, content.size.width, content.size.height);
    NSRect wantFrame   = [gWindow frameRectForContentRect:wantContent];
    [gWindow setFrameOrigin:wantFrame.origin];
}

void SetWindowMinSize(int width, int height)
{
    if (!md_RequireWindow("SetWindowMinSize")) return;
    // CONTENT-area minimum — pairs with SetWindowSize (setContentSize) and GetScreenWidth/Height.
    // Constrains interactive (user-drag) resizing; AppKit does NOT retroactively resize the
    // current window, so a window already smaller keeps its size until the next resize.
    gWindow.contentMinSize = NSMakeSize(width, height);
}

void SetWindowMaxSize(int width, int height)
{
    if (!md_RequireWindow("SetWindowMaxSize")) return;
    // CONTENT-area maximum (same caveat as SetWindowMinSize: limits future resizing, doesn't
    // shrink the window now). contentMaxSize, not maxSize — maxSize would include the title bar.
    gWindow.contentMaxSize = NSMakeSize(width, height);
}

void SetWindowOpacity(float opacity)
{
    if (!md_RequireWindow("SetWindowOpacity")) return;
    if (opacity < 0.0f) opacity = 0.0f;   // clamp to AppKit's valid [0,1] alpha range
    if (opacity > 1.0f) opacity = 1.0f;
    gWindow.alphaValue = opacity;   // whole-window translucency, title bar included
}

void SetWindowFocused(void)
{
    if (!md_RequireWindow("SetWindowFocused")) return;
    // Raise + make key (input focus). Like GLFW's focus path: no NSApp activate, so it reorders
    // our own windows without yanking the foreground away from another app the user is using.
    [gWindow makeKeyAndOrderFront:nil];
}

void HideWindow(void)
{
    if (!md_RequireWindow("HideWindow")) return;
    [gWindow orderOut:nil];   // off the screen list — IsWindowHidden() goes true (not miniaturized)
}

void UnhideWindow(void)
{
    if (!md_RequireWindow("UnhideWindow")) return;
    [gWindow orderFront:nil];   // back onto the screen list (doesn't steal key from another window)
}

void SetWindowTopmost(bool enabled)
{
    if (!md_RequireWindow("SetWindowTopmost")) return;
    // Floating level keeps the window above normal windows even when not key; Normal restores the
    // regular stacking order. Mirrors GLFW_FLOATING / raylib FLAG_WINDOW_TOPMOST.
    gWindow.level = enabled ? NSFloatingWindowLevel : NSNormalWindowLevel;
}

void ToggleFullscreen(void)
{
    if (!md_RequireWindow("ToggleFullscreen")) return;
    // Native macOS full-screen: animates into the window's OWN Space and auto-hides the menu bar.
    // Needs NSWindowCollectionBehaviorFullScreenPrimary (set in InitWindow). The transition is
    // ASYNC — windowDidResize: fires as the frame grows and re-syncs the Metal drawable for us;
    // IsWindowFullscreen() flips only once the transition commits (a query right after may lag).
    [gWindow toggleFullScreen:nil];
}

//MARK: - Window: State queries

// Live window-server state — main-thread only, nil-safe (false before InitWindow / after
// CloseWindow, like the size getters — no per-frame WARNING). Each pairs with an action above.

bool IsWindowMinimized(void)
{
    // Dock-miniaturized only (mirrors MinimizeWindow). Goes false the instant it's
    // deminiaturized — not a general "off screen" flag.
    return gWindow != nil && gWindow.miniaturized;
}

bool IsWindowMaximized(void)
{
    // isZoomed is COMPUTED by frame comparison, not a stored "we zoomed" flag: a window
    // dragged to fill the standard frame reads true; a zoomed one nudged off it reads false.
    // Unrelated to native full-screen (toggleFullScreen:) — that never shows up here.
    return gWindow != nil && gWindow.zoomed;
}

bool IsWindowFocused(void)
{
    // Key window = has keyboard/input focus (isKeyWindow, NOT isMainWindow). Correctly goes
    // false on app deactivation, so no need to also gate on NSApp.isActive.
    return gWindow != nil && gWindow.keyWindow;
}

bool IsWindowHidden(void)
{
    // "Hidden" = orderOut:'d (off the screen list) but NOT Dock-miniaturized. A miniaturized
    // window ALSO reports isVisible==NO, so AND-out miniaturization or a minimized window
    // gets misreported as hidden.
    return gWindow != nil && !gWindow.visible && !gWindow.miniaturized;
}

bool IsWindowFullscreen(void)
{
    // AppKit adds NSWindowStyleMaskFullScreen to the mask while in native full-screen. This is the
    // COMMITTED state — since toggleFullScreen: is async, it reflects the transition's end, not the
    // instant of the call. (Not NSView's isInFullScreenMode — that's the legacy enterFullScreenMode: API.)
    return gWindow != nil && (gWindow.styleMask & NSWindowStyleMaskFullScreen) != 0;
}

//MARK: - Window: Screen-space

bool IsWindowResized(void)
{
    return gWindowResized;
}

// Logical window size in POINTS — AppKit's coordinate space, what layout and
// (later) mouse events use. contentView.bounds is the content area below the
// title bar. Equal to gWindow.contentLayoutRect.size for our plain window;
// switch to contentLayoutRect the day we add a toolbar or full-size content view
// (only it excludes chrome). Nil-guard returns 0 silently — no per-frame WARNING
// flood, and honest before InitWindow / after CloseWindow.
int GetScreenWidth(void)
{
    if (gWindow == nil) return 0;
    return (int)gWindow.contentView.bounds.size.width;
}

int GetScreenHeight(void)
{
    if (gWindow == nil) return 0;
    return (int)gWindow.contentView.bounds.size.height;
}

// Physical framebuffer size in PIXELS — the size Metal actually renders into.
// convertSizeToBacking: is AppKit's designated points->pixels conversion; Apple
// says to use it INSTEAD of multiplying by backingScaleFactor ourselves. We read
// from the view, NOT from gMetalLayer.drawableSize — we're that layer's only
// writer, so reading it back would just echo what md_UpdateDrawableSize set.

int GetRenderWidth(void)
{
    if (gWindow == nil) return 0;
    return (int)md_ContentPixelSize().width;
}

int GetRenderHeight(void)
{
    if (gWindow == nil) return 0;
    return (int)md_ContentPixelSize().height;
}

// Window position = CONTENT-AREA top-left, TOP-LEFT origin, y DOWN, on the PRIMARY display —
// pairs with GetScreenWidth/Height (content size). AppKit's frame is bottom-left / y-up and
// INCLUDES the title bar, so contentRectForFrameRect: strips the bar (style-aware, never a
// hardcoded bar height) and we flip y against the primary-display height. Nil-guard returns 0
// silently, like the size getters (no per-frame WARNING). (int) truncation matches raylib.

int GetWindowPositionX(void)
{
    if (gWindow == nil) return 0;
    return (int)[gWindow contentRectForFrameRect:gWindow.frame].origin.x;
}

int GetWindowPositionY(void)
{
    if (gWindow == nil) return 0;
    NSRect content = [gWindow contentRectForFrameRect:gWindow.frame];
    // Distance from the TOP of the primary display down to the content's TOP edge.
    return (int)(md_PrimaryDisplayHeight() - (content.origin.y + content.size.height));
}

// Backing scale of the window's current display: 1.0 non-Retina, 2.0 Retina — the same ratio
// GetRenderWidth/GetScreenWidth reflect. macOS scale is uniform, so one float suffices (raylib
// returns a Vector2 with x==y here). Returns 1.0 with no window — a neutral scale, deliberately
// NOT the size getters' 0 (a 0 scale would be a divide-by-zero trap for callers).
float GetWindowScaleDPI(void)
{
    if (gWindow == nil) return 1.0f;
    return (float)gWindow.backingScaleFactor;
}

//MARK: - Monitors

// Monitors are indexed into [NSScreen screens] (ordering is stable within a session; index 0 is
// NOT guaranteed to be the primary). Sizes/positions are in POINTS — consistent with GetScreen*
// and window position, and matching raylib on macOS (GLFW video modes are screen-coordinates =
// points too). Out-of-range index warns once and returns a safe 0.
static NSScreen *md_ScreenAt(int monitor, const char *fn)
{
    NSScreen *result = nil;
    @autoreleasepool {   // [NSScreen screens] returns an autoreleased array — drain it here
        NSArray<NSScreen *> *screens = [NSScreen screens];
        if (monitor < 0 || monitor >= (int)screens.count) {
            TraceLog(MD_LOG_WARNING, "%s: monitor %d out of range (have %d)", fn, monitor, (int)screens.count);
        } else {
            result = screens[monitor];   // system-owned; stays valid after the pool drains (ARC retains)
        }
    }
    return result;
}

int GetMonitorCount(void)
{
    @autoreleasepool { return (int)[NSScreen screens].count; }
}

int GetCurrentMonitor(void)
{
    if (gWindow == nil) return 0;
    @autoreleasepool {
        NSScreen *screen = gWindow.screen;   // nil if the window is fully offscreen
        if (screen == nil) return 0;
        NSUInteger idx = [[NSScreen screens] indexOfObject:screen];   // pointer identity
        return (idx == NSNotFound) ? 0 : (int)idx;
    }
}

int GetMonitorWidth(int monitor)
{
    NSScreen *screen = md_ScreenAt(monitor, "GetMonitorWidth");
    return screen ? (int)screen.frame.size.width : 0;
}

int GetMonitorHeight(int monitor)
{
    NSScreen *screen = md_ScreenAt(monitor, "GetMonitorHeight");
    return screen ? (int)screen.frame.size.height : 0;
}

int GetMonitorRefreshRate(int monitor)
{
    NSScreen *screen = md_ScreenAt(monitor, "GetMonitorRefreshRate");
    // maximumFramesPerSecond (macOS 12+): max refresh in Hz — 60, or 120 on ProMotion. Avoids
    // CGDisplayModeGetRefreshRate, which returns 0 for built-in Apple displays.
    return screen ? (int)screen.maximumFramesPerSecond : 0;
}

int GetMonitorPositionX(int monitor)
{
    NSScreen *screen = md_ScreenAt(monitor, "GetMonitorPositionX");
    return screen ? (int)screen.frame.origin.x : 0;
}

int GetMonitorPositionY(int monitor)
{
    NSScreen *screen = md_ScreenAt(monitor, "GetMonitorPositionY");
    if (screen == nil) return 0;
    // Flip to top-left origin like GetWindowPositionY: top edge measured down from the primary.
    NSRect f = screen.frame;
    return (int)(md_PrimaryDisplayHeight() - (f.origin.y + f.size.height));
}

const char *GetMonitorName(int monitor)
{
    NSScreen *screen = md_ScreenAt(monitor, "GetMonitorName");
    // Copy out: localizedName's UTF8String is autoreleased (freed when a pool drains), so we
    // can't hand the caller that pointer. Static buffer -> valid until the next call (raylib's
    // contract). Main-thread only, so the shared buffer is not a data race.
    static char nameBuf[256];
    @autoreleasepool {
        const char *name = screen ? screen.localizedName.UTF8String : "";
        snprintf(nameBuf, sizeof nameBuf, "%s", name ? name : "");
    }
    return nameBuf;
}

void SetWindowMonitor(int monitor)
{
    if (!md_RequireWindow("SetWindowMonitor")) return;
    NSScreen *screen = md_ScreenAt(monitor, "SetWindowMonitor");
    if (screen == nil) return;
    if (IsWindowFullscreen()) return;   // same as SetWindowPosition: don't move a fullscreen
                                        // window's Space via setFrameOrigin (defined no-op)
    // Center the window in the target monitor's visibleFrame (excludes menu bar + Dock), keeping
    // its current size — moving a windowed app to another display. Not clamped: a window larger
    // than the target simply overflows, matching how a manual drag would leave it.
    NSRect vis = screen.visibleFrame;
    NSRect win = gWindow.frame;
    CGFloat x = vis.origin.x + (vis.size.width  - win.size.width)  * 0.5;
    CGFloat y = vis.origin.y + (vis.size.height - win.size.height) * 0.5;
    [gWindow setFrameOrigin:NSMakePoint(x, y)];
}

//MARK: - Timing section

double GetTime(void)
{
    if (gStartTime <= 0.0) return 0.0;   // before InitWindow: honest 0, not system uptime
    return CACurrentMediaTime() - gStartTime;
}

float GetFrameTime(void)
{
    return gFrameTime;
}

int GetFPS(void)
{
    if (gFrameTimeAvg <= 0.0f) return 0;
    return (int)(1.0 / (double)gFrameTimeAvg + 0.5);   // round to nearest (double precision)
}

void WaitTime(double seconds)
{
    if (seconds <= 0.0) return;

    // Cache the ticks->nanoseconds ratio once. NOT identity on Apple Silicon (~125/3,
    // ~41.67 ns/tick) — the conversion is required. Guard BOTH fields: numer is the divisor.
    static mach_timebase_info_data_t tb = {0, 0};
    if (tb.denom == 0 || tb.numer == 0) mach_timebase_info(&tb);
    if (tb.numer == 0) return;   // mach_timebase_info unavailable (never on supported HW) — avoid /0

    // 128-bit intermediate so `ns * denom` can't overflow uint64 for very long waits.
    uint64_t ns    = (uint64_t)(seconds * 1e9);
    uint64_t ticks = (uint64_t)(((__uint128_t)ns * tb.denom) / tb.numer);
    mach_wait_until(mach_absolute_time() + ticks);   // sleep until an absolute deadline on our clock
}

void SetTargetFPS(int fps)
{
    if (fps <= 0) { gTargetFPS = 0.0; return; }   // 0 or negative => uncapped
    if (fps < 10) fps = 10;                        // floor: WWDC warns presenting
                                                   // below the panel minimum can drop
                                                   // the display (tunable)
    gTargetFPS = (double)fps;
}


//MARK: - Drawing: Frame

void BeginDrawing(void)
{
    // No live pipeline (before InitWindow / after CloseWindow / failed init): skip silently,
    // like the getters — no per-frame WARNING flood. A drawable miss with a LIVE layer still
    // warns below (a real transient, not teardown).
    if (gMetalLayer == nil || gCommandQueue == nil) return;

    // Per-frame pool: nextDrawable/commandBuffer autorelease. gDrawable/gCommandBuffer are
    // STRONG globals, so they survive this drain (it only consumes the pending autorelease)
    // and are released deterministically when nil'd in EndDrawing — so the 3-drawable pool
    // never accumulates. No pool spanning Begin->End is needed.
    @autoreleasepool {
        gDrawable = [gMetalLayer nextDrawable];
        if (gDrawable == nil) {
            TraceLog(MD_LOG_WARNING, "BeginDrawing: no drawable available, skipping frame");
            return;
        }
        gCommandBuffer = [gCommandQueue commandBuffer];
    }
}

void ClearBackground(Color color)
{
    // Per-frame pool: the render-pass descriptor + encoder are autoreleased locals.
    @autoreleasepool {
        if (gDrawable == nil || gCommandBuffer == nil) return;   // BeginDrawing already reported the miss

        MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture = gDrawable.texture;
        pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        pass.colorAttachments[0].storeAction = MTLStoreActionStore;
        pass.colorAttachments[0].clearColor = MTLClearColorMake(color.r / 255.0,
                                                                color.g / 255.0,
                                                                color.b / 255.0,
                                                                color.a / 255.0);

        // Local, not a global: the encoder lives entirely within this call (created and
        // ended here). Frame-spanning encoder state gets designed deliberately at M3.
        id<MTLRenderCommandEncoder> encoder = [gCommandBuffer renderCommandEncoderWithDescriptor:pass];
        [encoder endEncoding];
    }
}

void EndDrawing(void)
{
    // Clear the resize flag at frame END (after the frame's IsWindowResized() check), so a
    // resize is visible for its whole frame — including programmatic SetWindowSize, whose
    // windowDidResize: fires synchronously (not via the event drain).
    gWindowResized = false;

    bool didPresent = (gDrawable != nil && gCommandBuffer != nil);

    if (didPresent) {
        // Surface GPU-side faults on a Metal background thread (our only off-main code): reads
        // only the passed-in cb + thread-safe TraceLog, takes cb as a PARAMETER (no retain
        // cycle), and pools its own autoreleased NSString. Plain vsync present — the CPU cap
        // below enforces the rate (afterMinimumDuration: was unreliable on a manual layer).
        [gCommandBuffer addCompletedHandler:^(id<MTLCommandBuffer> cb) {
            @autoreleasepool {
                if (cb.error) {
                    TraceLog(MD_LOG_ERROR, "EndDrawing: GPU error: %s",
                             cb.error.localizedDescription.UTF8String);
                }
            }
        }];
        @autoreleasepool {
            [gCommandBuffer presentDrawable:gDrawable];
            [gCommandBuffer commit];
        }
    }
    // Release every frame (presented or not) so an acquired-but-unpresented drawable —
    // e.g. commandBuffer returned nil — is returned to the pool immediately.
    gDrawable = nil;
    gCommandBuffer = nil;

    // Frame timing + CPU rate cap (raylib work/wait model).
    double now = CACurrentMediaTime();

    // Establish the baseline off the first frame that actually PRESENTED — a startup skip
    // must not seed timing (this also excludes InitWindow->loop setup time from frame 0).
    if (gPrevFrameTime <= 0.0) {
        if (didPresent) gPrevFrameTime = now;
        return;
    }

    // Cap runs every frame, so the loop is paced even when a frame skipped (never spins).
    if (gTargetFPS > 0.0) {
        double target = 1.0 / gTargetFPS;
        double work = now - gPrevFrameTime;
        if (work < target) {
            WaitTime(target - work);
            now = CACurrentMediaTime();
        }
    }

    // Measure frame time / FPS only on presented frames — skipped frames don't pollute it.
    if (didPresent) {
        gFrameTime = (float)(now - gPrevFrameTime);   // total period, includes any cap wait
        if (gFrameTimeAvg <= 0.0f) gFrameTimeAvg = gFrameTime;               // seed
        else gFrameTimeAvg = gFrameTimeAvg * 0.90f + gFrameTime * 0.10f;
    }
    gPrevFrameTime = now;   // always advance the cap reference
}
