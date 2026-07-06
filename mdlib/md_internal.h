#ifndef MD_INTERNAL_H
#define MD_INTERNAL_H

// PRIVATE shared header — NOT part of the public API, NOT shipped. It holds ONLY the state and
// hooks that genuinely cross .mm files (the "minimal externs" decision from the charter). Included
// by the .mm implementation files, never by user code (which sees only metaldraw.h).

@class NSWindow;
@class NSEvent;

// Defined in md_core.mm. Shared so md_input.mm can reach the window (mouse-coordinate conversion,
// cursor warping — arriving in later input steps). The ONLY cross-file global for now; everything
// else in md_core.mm stays file-static.
extern NSWindow *gWindow;

// Input plumbing — defined in md_input.mm, driven by md_core.mm's event pump.
void md_ProcessEvent(NSEvent *event);   // inspect one NSEvent, update the input state tables
void md_PollInputSnapshot(void);        // once per frame (before the drain): current -> previous
void md_ResetKeyStates(void);           // clear held keys on focus loss (prevents stuck keys)
int  md_MapKeyCode(unsigned short keyCode);   // macOS keyCode -> MD_KEY_* (exposed for the keymap test)

#endif // MD_INTERNAL_H
