#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

#include "metaldraw.h"
#include <mach/mach_time.h>   // mach_wait_until / mach_timebase_info

@interface MDWindowDelegate : NSObject <NSWindowDelegate>
@end


//MARK: - Global state (private to this file)

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

- (void)windowDidResize:(NSNotification *)notification {
    gWindowResized = true;
    md_UpdateDrawableSize();
}

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
    gMetalLayer.drawableSize = md_ContentPixelSize();
}


//MARK: - Window: Lifecycle

void InitWindow(int width, int height, const char *title)
{
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    NSRect frame = NSMakeRect(0, 0, width, height);
    NSWindowStyleMask style = NSWindowStyleMaskTitled
                            | NSWindowStyleMaskClosable
                            | NSWindowStyleMaskMiniaturizable
                            | NSWindowStyleMaskResizable;
    gWindow = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:style
                                            backing:NSBackingStoreBuffered
                                              defer:NO];

    [gWindow setTitle:[NSString stringWithUTF8String:title]];
    [gWindow center];

    gWindowDelegate = [[MDWindowDelegate alloc] init];
    gWindow.delegate = gWindowDelegate;

    gWindow.collectionBehavior = NSWindowCollectionBehaviorFullScreenAuxiliary;

    // Metal setup
    gDevice = MTLCreateSystemDefaultDevice();
    gCommandQueue = [gDevice newCommandQueue];

    gMetalLayer = [CAMetalLayer layer];
    gMetalLayer.device = gDevice;
    gMetalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;

    NSView *contentView = gWindow.contentView;
    contentView.layer = gMetalLayer;
    contentView.wantsLayer = YES;

    gMetalLayer.contentsScale = gWindow.backingScaleFactor;
    md_UpdateDrawableSize();

    TraceLog(MD_LOG_INFO, "MetalDraw: GPU = %s", gDevice.name.UTF8String);

    [gWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    // Monotonic clock start. CACurrentMediaTime() is mach_absolute_time in seconds
    // (pauses during system sleep — desirable, no post-wake delta spike).
    gStartTime = CACurrentMediaTime();
    gPrevFrameTime = 0.0;   // baseline is set at the FIRST EndDrawing, not from setup time
}

bool WindowShouldClose(void)
{
    gWindowResized = false;   // clear last frame's flag before draining new events

    NSEvent *event;
    while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                       untilDate:[NSDate distantPast]
                                          inMode:NSDefaultRunLoopMode
                                         dequeue:YES]) != nil)
    {
        [NSApp sendEvent:event];
    }
    return gShouldClose;
}

void CloseWindow(void)
{
    [gWindow close];
    gWindow = nil;
    gWindowDelegate = nil;
}


//MARK: - Window: Management

void SetWindowTitle(const char *title)
{
    if (gWindow == nil) {
        TraceLog(MD_LOG_WARNING, "SetWindowTitle: no window (call InitWindow first)");
        return;
    }
    gWindow.title = [NSString stringWithUTF8String:title];
}

void MinimizeWindow(void)
{
    if (gWindow == nil) {
        TraceLog(MD_LOG_WARNING, "MinimizeWindow: no window (call InitWindow first)");
        return;
    }
    [gWindow miniaturize:nil];
}

void MaximizeWindow(void)
{
    if (gWindow == nil) {
        TraceLog(MD_LOG_WARNING, "MaximizeWindow: no window (call InitWindow first)");
        return;
    }
    [gWindow zoom:nil];   // macOS "zoom" — the nearest native equivalent to maximize
}

void RestoreWindow(void)
{
    if (gWindow == nil) {
        TraceLog(MD_LOG_WARNING, "RestoreWindow: no window (call InitWindow first)");
        return;
    }
    [gWindow deminiaturize:nil];
}

void SetWindowSize(int width, int height)
{
    if (gWindow == nil)
    {
        TraceLog(MD_LOG_WARNING, "SetWindowSize: no window (call InitWindow first)");
        return;
    }
    // Sets the CONTENT area in points (the mirror of GetScreenWidth/Height). This
    // resizes the window's frame, which fires windowDidResize: -> our
    // md_UpdateDrawableSize() re-syncs the Metal drawable for us, no manual poke.
    [gWindow setContentSize:NSMakeSize(width, height)];
}

void SetWindowResizable(bool resizable)
{
    if (gWindow == nil) {
        TraceLog(MD_LOG_WARNING, "SetWindowResizable: no window (call InitWindow first)");
        return;
    }
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
    return (int)(1.0f / gFrameTimeAvg + 0.5f);   // round to nearest
}

void WaitTime(double seconds)
{
    if (seconds <= 0.0) return;

    // Cache the ticks->nanoseconds ratio once. NOT identity on Apple Silicon
    // (numer/denom is ~125/3, i.e. ~41.67 ns/tick) — the conversion below is required;
    // dropping it would make every sleep ~42x too long.
    static mach_timebase_info_data_t tb = {0, 0};
    if (tb.denom == 0) mach_timebase_info(&tb);

    uint64_t ns       = (uint64_t)(seconds * 1e9);
    uint64_t deadline = mach_absolute_time() + (ns * tb.denom) / tb.numer;
    mach_wait_until(deadline);   // sleep until an absolute deadline on our clock
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
    gDrawable = [gMetalLayer nextDrawable];
    if (gDrawable == nil) {
        TraceLog(MD_LOG_WARNING, "BeginDrawing: no drawable available, skipping frame");
        return;
    }

    gCommandBuffer = [gCommandQueue commandBuffer];
}

void ClearBackground(Color color)
{
    if (gDrawable == nil || gCommandBuffer == nil) {
        TraceLog(MD_LOG_WARNING, "ClearBackground: no drawable/command buffer, skipping");
        return;
    }

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

void EndDrawing(void)
{
    // Present the frame (plain, vsync-scheduled). We reverted the native
    // presentDrawable:afterMinimumDuration: throttle: on a hand-managed CAMetalLayer
    // here it was unreliable — the compositor released drawables after one refresh
    // instead of holding them 1/target s, so nextDrawable never back-pressured and the
    // loop escaped to the panel refresh (the 30->120->30 flapping). The rate cap is
    // now enforced on the CPU below, which is predictable and verifiable.
    if (gDrawable != nil && gCommandBuffer != nil) {
        [gCommandBuffer presentDrawable:gDrawable];
        [gCommandBuffer commit];
        gDrawable = nil;
        gCommandBuffer = nil;
    } else {
        TraceLog(MD_LOG_WARNING, "EndDrawing: no drawable/command buffer, skipping present");
    }

    // Frame timing + rate cap at end-of-frame (raylib work/wait model): measure the
    // work this frame took; if a target is set, sleep the remainder so the period is
    // >= 1/target. WaitTime() (mach_wait_until) enforces it precisely on the CPU.
    double now = CACurrentMediaTime();

    // First real frame: just establish the baseline. Measuring now-gPrevFrameTime
    // here would fold all of InitWindow->loop setup into frame 0, inflating
    // gFrameTime and mis-seeding the FPS average for ~20 frames.
    if (gPrevFrameTime <= 0.0) {
        gPrevFrameTime = now;
        return;
    }

    double work = now - gPrevFrameTime;

    if (gTargetFPS > 0.0) {
        double target = 1.0 / gTargetFPS;
        if (work < target) {
            WaitTime(target - work);
            now = CACurrentMediaTime();
        }
    }

    gFrameTime = (float)(now - gPrevFrameTime);   // total period, includes any cap wait
    gPrevFrameTime = now;

    // Smoothed frame time (EMA) -> stable GetFPS.
    if (gFrameTimeAvg <= 0.0f) gFrameTimeAvg = gFrameTime;               // seed
    else gFrameTimeAvg = gFrameTimeAvg * 0.90f + gFrameTime * 0.10f;
}
