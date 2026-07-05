#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

#include "metaldraw.h"


@interface MDWindowDelegate : NSObject <NSWindowDelegate>
@end

static bool gShouldClose = false;
static NSWindow *gWindow = nil;
static id<MTLDevice> gDevice = nil;
static id<MTLCommandQueue> gCommandQueue = nil;
static CAMetalLayer *gMetalLayer = nil;
static MDWindowDelegate *gWindowDelegate = nil;
static id<CAMetalDrawable> gDrawable = nil;
static id<MTLRenderCommandEncoder> gEncoder = nil;
static id<MTLCommandBuffer> gCommandBuffer = nil;


@implementation MDWindowDelegate
- (BOOL)windowShouldClose:(NSWindow *)sender {
    gShouldClose = true;
    return NO;
}
@end


void InitWindow(int width, int height, const char *title)
{

[NSApplication sharedApplication];
[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

NSRect frame = NSMakeRect(0,0,width,height);
NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;

gWindow = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:style
                                          backing:NSBackingStoreBuffered
                                          defer:NO];

[gWindow setTitle:[NSString stringWithUTF8String:title]];
[gWindow center];
gWindowDelegate = [[MDWindowDelegate alloc] init];
gWindow.delegate = gWindowDelegate;


//MARK: Metal setup
gDevice = MTLCreateSystemDefaultDevice();
gCommandQueue = [gDevice newCommandQueue];

gMetalLayer = [CAMetalLayer layer];
gMetalLayer.device = gDevice;
gMetalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;

NSView *contentView = gWindow.contentView;
contentView.layer = gMetalLayer;
contentView.wantsLayer = YES;

CGFloat scale = gWindow.backingScaleFactor;
gMetalLayer.contentsScale = scale;
gMetalLayer.drawableSize = CGSizeMake(contentView.bounds.size.width * scale,
                                       contentView.bounds.size.height * scale);
    NSLog(@"MetalDraw: GPU = %@", gDevice.name);



[gWindow makeKeyAndOrderFront:nil];
[NSApp activateIgnoringOtherApps:YES];

}

bool WindowShouldClose(void){
    NSEvent *event;
    while((event = [NSApp nextEventMatchingMask: NSEventMaskAny 
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


void BeginDrawing(void)
{
    gDrawable = [gMetalLayer nextDrawable];
    if (gDrawable == nil) {
        NSLog(@"MetalDraw: Failed to get next drawable");
        return;
    }

    gCommandBuffer = [gCommandQueue commandBuffer];
}

void ClearBackground(Color color)
{
    if (gDrawable == nil || gCommandBuffer == nil) {
        NSLog(@"MetalDraw: Cannot clear background, drawable or command buffer is nil");
        return;
    }

    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = gDrawable.texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(color.r / 255.0, color.g / 255.0, color.b / 255.0, color.a / 255.0);
    
    gEncoder = [gCommandBuffer renderCommandEncoderWithDescriptor:pass];
    [gEncoder endEncoding];

}

void EndDrawing(void)
{
    if (gDrawable == nil || gCommandBuffer == nil) {
        NSLog(@"MetalDraw: Cannot end drawing, drawable or command buffer is nil");
        return;
    }

    [gCommandBuffer presentDrawable:gDrawable];
    [gCommandBuffer commit];

    gDrawable = nil;
    gCommandBuffer = nil;
}