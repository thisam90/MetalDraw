#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

#include "metaldraw.h"


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
static id<MTLRenderCommandEncoder> gEncoder = nil;
static id<MTLCommandBuffer> gCommandBuffer = nil;

static double gStartTime     = 0.0;
static double gPrevFrameTime = 0.0;
static float  gFrameTime     = 0.0f;
static float  gFrameTimeAvg  = 0.0f;

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


static void md_UpdateDrawableSize(void)
{
       if (gWindow == nil || gMetalLayer == nil) return;

    // Points -> pixels via AppKit's backing conversion (Apple's guidance: use
    // this, not a manual * backingScaleFactor). It's the SAME expression
    // GetRenderWidth/Height use, so the drawable we render into and the size we
    // report are computed identically and can't drift apart.
    NSView *contentView = gWindow.contentView;
    gMetalLayer.drawableSize = [contentView convertSizeToBacking:contentView.bounds.size];
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
    gPrevFrameTime = gStartTime;
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
    NSView *view = gWindow.contentView;
    NSSize px = [view convertSizeToBacking:view.bounds.size];
    return (int)px.width;
}

int GetRenderHeight(void)
{
    if (gWindow == nil) return 0;
    NSView *view = gWindow.contentView;
    NSSize px = [view convertSizeToBacking:view.bounds.size];
    return (int)px.height;
}

//MARK: - Timing section

double GetTime(void)
{
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

    gEncoder = [gCommandBuffer renderCommandEncoderWithDescriptor:pass];
    [gEncoder endEncoding];
}

void EndDrawing(void)
{
     // Frame delta = full loop period; measured even on skipped frames.
    double now = CACurrentMediaTime();
    gFrameTime = (float)(now - gPrevFrameTime);
    gPrevFrameTime = now;

        // Smoothed frame time (exponential moving average) -> stable GetFPS.
    if (gFrameTimeAvg <= 0.0f) gFrameTimeAvg = gFrameTime;              // seed
    else gFrameTimeAvg = gFrameTimeAvg * 0.90f + gFrameTime * 0.10f;



    if (gDrawable == nil || gCommandBuffer == nil) {
        TraceLog(MD_LOG_WARNING, "EndDrawing: no drawable/command buffer, skipping");
        return;
    }

    [gCommandBuffer presentDrawable:gDrawable];
    [gCommandBuffer commit];

    gDrawable = nil;
    gCommandBuffer = nil;
}
