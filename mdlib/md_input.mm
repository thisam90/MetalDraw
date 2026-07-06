#import <Cocoa/Cocoa.h>

#include "metaldraw.h"
#include "md_internal.h"
#include <string.h>   // memcpy

//MARK: - Keyboard state (private to this file)

// raylib-style immediate mode: two frames of key state, indexed by MD_KEY_* value (== raylib's
// KeyboardKey value). Sized past our current max (MD_KEY_UP = 265); 512 leaves room for the rest
// of the raylib key set as we add it.
#define MD_MAX_KEYS 512
static bool gKeyCurrent[MD_MAX_KEYS];
static bool gKeyPrevious[MD_MAX_KEYS];

// macOS NSEvent.keyCode is a PHYSICAL, layout-independent virtual keycode (identical to the Carbon
// kVK_ constants) — the ANSI-A-position key reports 0 on QWERTY/AZERTY/Dvorak alike. Maps a keyCode
// to its MD_KEY_* value (incl. modifiers, which arrive via flagsChanged). macOS keyCodes are NOT
// alphabetical (positional); every value cross-checked by an independent 3-way audit. Non-static so
// the keymap test can verify the whole table. Returns MD_KEY_NULL (0) for keys with no Mac keycode.
int md_MapKeyCode(unsigned short keyCode)
{
    switch (keyCode) {
        // Letters
        case 0:  return MD_KEY_A;   case 11: return MD_KEY_B;   case 8:  return MD_KEY_C;
        case 2:  return MD_KEY_D;   case 14: return MD_KEY_E;   case 3:  return MD_KEY_F;
        case 5:  return MD_KEY_G;   case 4:  return MD_KEY_H;   case 34: return MD_KEY_I;
        case 38: return MD_KEY_J;   case 40: return MD_KEY_K;   case 37: return MD_KEY_L;
        case 46: return MD_KEY_M;   case 45: return MD_KEY_N;   case 31: return MD_KEY_O;
        case 35: return MD_KEY_P;   case 12: return MD_KEY_Q;   case 15: return MD_KEY_R;
        case 1:  return MD_KEY_S;   case 17: return MD_KEY_T;   case 32: return MD_KEY_U;
        case 9:  return MD_KEY_V;   case 13: return MD_KEY_W;   case 7:  return MD_KEY_X;
        case 16: return MD_KEY_Y;   case 6:  return MD_KEY_Z;
        // Digits
        case 29: return MD_KEY_ZERO;   case 18: return MD_KEY_ONE;    case 19: return MD_KEY_TWO;
        case 20: return MD_KEY_THREE;  case 21: return MD_KEY_FOUR;   case 23: return MD_KEY_FIVE;
        case 22: return MD_KEY_SIX;    case 26: return MD_KEY_SEVEN;  case 28: return MD_KEY_EIGHT;
        case 25: return MD_KEY_NINE;
        // Punctuation
        case 27: return MD_KEY_MINUS;         case 24: return MD_KEY_EQUAL;
        case 33: return MD_KEY_LEFT_BRACKET;  case 30: return MD_KEY_RIGHT_BRACKET;
        case 42: return MD_KEY_BACKSLASH;     case 41: return MD_KEY_SEMICOLON;
        case 39: return MD_KEY_APOSTROPHE;    case 50: return MD_KEY_GRAVE;
        case 43: return MD_KEY_COMMA;         case 47: return MD_KEY_PERIOD;
        case 44: return MD_KEY_SLASH;
        // Special / navigation
        case 49:  return MD_KEY_SPACE;      case 53:  return MD_KEY_ESCAPE;
        case 36:  return MD_KEY_ENTER;      case 48:  return MD_KEY_TAB;
        case 51:  return MD_KEY_BACKSPACE;  case 117: return MD_KEY_DELETE;
        case 115: return MD_KEY_HOME;       case 119: return MD_KEY_END;
        case 116: return MD_KEY_PAGE_UP;    case 121: return MD_KEY_PAGE_DOWN;
        case 123: return MD_KEY_LEFT;       case 124: return MD_KEY_RIGHT;
        case 125: return MD_KEY_DOWN;       case 126: return MD_KEY_UP;
        case 57:  return MD_KEY_CAPS_LOCK;
        // Function
        case 122: return MD_KEY_F1;    case 120: return MD_KEY_F2;    case 99:  return MD_KEY_F3;
        case 118: return MD_KEY_F4;    case 96:  return MD_KEY_F5;    case 97:  return MD_KEY_F6;
        case 98:  return MD_KEY_F7;    case 100: return MD_KEY_F8;    case 101: return MD_KEY_F9;
        case 109: return MD_KEY_F10;   case 103: return MD_KEY_F11;   case 111: return MD_KEY_F12;
        // Keypad
        case 82: return MD_KEY_KP_0;   case 83: return MD_KEY_KP_1;   case 84: return MD_KEY_KP_2;
        case 85: return MD_KEY_KP_3;   case 86: return MD_KEY_KP_4;   case 87: return MD_KEY_KP_5;
        case 88: return MD_KEY_KP_6;   case 89: return MD_KEY_KP_7;   case 91: return MD_KEY_KP_8;
        case 92: return MD_KEY_KP_9;   case 65: return MD_KEY_KP_DECIMAL;
        case 75: return MD_KEY_KP_DIVIDE;    case 67: return MD_KEY_KP_MULTIPLY;
        case 78: return MD_KEY_KP_SUBTRACT;  case 69: return MD_KEY_KP_ADD;
        case 76: return MD_KEY_KP_ENTER;     case 81: return MD_KEY_KP_EQUAL;
        // Modifiers (delivered via flagsChanged, never keyDown/keyUp)
        case 56: return MD_KEY_LEFT_SHIFT;    case 60: return MD_KEY_RIGHT_SHIFT;
        case 59: return MD_KEY_LEFT_CONTROL;  case 62: return MD_KEY_RIGHT_CONTROL;
        case 58: return MD_KEY_LEFT_ALT;      case 61: return MD_KEY_RIGHT_ALT;
        case 55: return MD_KEY_LEFT_SUPER;    case 54: return MD_KEY_RIGHT_SUPER;

        default: return MD_KEY_NULL;   // no Mac keycode (Insert, ScrollLock, NumLock, PrtScr, Pause, fn, ...)
    }
}

// For a modifier keyCode, the device-DEPENDENT (low-word) modifierFlags bit that reflects THAT
// exact left/right key's state — so flagsChanged can tell down from up per side. The device-
// INDEPENDENT class bit can't: it stays set while EITHER side of a pair is held. CapsLock has no
// side bit, so we use its device-independent latch. Returns 0 for a non-modifier keyCode. (IOKit
// NX_ device masks: informally documented but de-facto stable, same bits GLFW/SDL use.)
static NSEventModifierFlags md_ModifierMask(unsigned short keyCode)
{
    switch (keyCode) {
        case 56: return 0x0002;   // left shift
        case 60: return 0x0004;   // right shift
        case 59: return 0x0001;   // left control
        case 62: return 0x2000;   // right control
        case 58: return 0x0020;   // left option / alt
        case 61: return 0x0040;   // right option / alt
        case 55: return 0x0008;   // left command
        case 54: return 0x0010;   // right command
        case 57: return NSEventModifierFlagCapsLock;   // caps-lock latch (0x10000, device-independent)
        default: return 0;
    }
}

//MARK: - Event intake (called from md_core.mm's pump, once per NSEvent)

// Single bool per key (raylib-parity immediate mode): if a key's down AND up both arrive within
// one frame's drain, 'current' ends false and the tap collapses to no edge — IsKeyPressed and
// IsKeyReleased miss that sub-frame press. This matches raylib's GLFW backend exactly (same
// current/previous snapshot), so it's an accepted limitation, not a divergence to "fix".
void md_ProcessEvent(NSEvent *event)
{
    switch (event.type) {
        case NSEventTypeKeyDown: {
            if (event.isARepeat) break;   // OS auto-repeat, not a new physical press (state already set)
            int key = md_MapKeyCode(event.keyCode);
            if (key > MD_KEY_NULL && key < MD_MAX_KEYS) gKeyCurrent[key] = true;
            break;
        }
        case NSEventTypeKeyUp: {
            int key = md_MapKeyCode(event.keyCode);
            if (key > MD_KEY_NULL && key < MD_MAX_KEYS) gKeyCurrent[key] = false;
            break;
        }
        case NSEventTypeFlagsChanged: {
            // Modifiers never fire keyDown/keyUp — only flagsChanged, once per press AND per
            // release, both carrying the same keyCode with no down/up bit. Infer the edge by
            // testing that key's own device-mask bit in the current modifierFlags (set = down).
            NSEventModifierFlags mask = md_ModifierMask(event.keyCode);
            if (mask == 0) break;
            int key = md_MapKeyCode(event.keyCode);
            if (key > MD_KEY_NULL && key < MD_MAX_KEYS) {
                gKeyCurrent[key] = (event.modifierFlags & mask) != 0;
            }
            break;
        }
        default: break;   // mouse / scroll land in later input steps
    }
}

//MARK: - Per-frame snapshot (called once per frame from WindowShouldClose, before the drain)

void md_PollInputSnapshot(void)
{
    // Roll current -> previous so IsKeyPressed/IsKeyReleased can detect this-frame edges. Runs
    // BEFORE the event drain, so "previous" = state at the end of last frame and "current" then
    // picks up this frame's presses/releases as the drain feeds md_ProcessEvent.
    memcpy(gKeyPrevious, gKeyCurrent, sizeof gKeyCurrent);
}

void md_ResetKeyStates(void)
{
    // Called on focus loss (windowDidResignKey:). A key/modifier RELEASE is delivered only to the
    // app that's frontmost when it happens — so a key held while the user Cmd-Tabs away would
    // otherwise latch "down" forever (its release lands in the other app). Zero CURRENT only: the
    // next md_PollInputSnapshot leaves previous=held / current=cleared, so held keys still get one
    // clean IsKeyReleased edge (zeroing previous too would swallow it). Matches GLFW/SDL/raylib.
    memset(gKeyCurrent, 0, sizeof gKeyCurrent);
}

//MARK: - Keyboard queries (public API)

bool IsKeyPressed(int key)
{
    if (key <= MD_KEY_NULL || key >= MD_MAX_KEYS) return false;
    return gKeyCurrent[key] && !gKeyPrevious[key];   // down now, up last frame
}

bool IsKeyDown(int key)
{
    if (key <= MD_KEY_NULL || key >= MD_MAX_KEYS) return false;
    return gKeyCurrent[key];
}

bool IsKeyReleased(int key)
{
    if (key <= MD_KEY_NULL || key >= MD_MAX_KEYS) return false;
    return !gKeyCurrent[key] && gKeyPrevious[key];   // up now, down last frame
}

bool IsKeyUp(int key)
{
    if (key <= MD_KEY_NULL || key >= MD_MAX_KEYS) return false;
    return !gKeyCurrent[key];
}
