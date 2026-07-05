#import <Cocoa/Cocoa.h>
#include "metaldraw.h"

@interface MDWindowDelegate : NSObject <NSWindowDelegate>
@end

static bool gShouldClose = false;
static NSWindow *gWindow = nil;
static MDWindowDelegate *gWindowDelegate = nil;

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