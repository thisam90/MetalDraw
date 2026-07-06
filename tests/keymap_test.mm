// Automated keyboard-mapping test — headless, no window. Verifies:
//   1. (compile time) the KeyboardKey enum values match raylib's KeyboardKey exactly.
//   2. (run time) md_MapKeyCode() maps every macOS keyCode to the correct MD_KEY_*, and returns
//      MD_KEY_NULL for codes that have no key on a Mac.
// Exit code 0 = all pass, 1 = one or more mismatches (so it can gate a build/CI).
//
// Build & run:
//   clang++ -fobjc-arc -Imdlib tests/keymap_test.mm mdlib/md_input.mm -framework Cocoa -o keymap_test
//   ./keymap_test
#include "metaldraw.h"
#include "md_internal.h"
#include <stdio.h>

// ---- Compile-time: enum values must equal raylib's KeyboardKey ------------------------------
static_assert(MD_KEY_APOSTROPHE == 39,  "MD_KEY_APOSTROPHE");
static_assert(MD_KEY_SPACE      == 32,  "MD_KEY_SPACE");
static_assert(MD_KEY_ZERO       == 48,  "MD_KEY_ZERO");
static_assert(MD_KEY_NINE       == 57,  "MD_KEY_NINE");
static_assert(MD_KEY_A          == 65,  "MD_KEY_A");
static_assert(MD_KEY_Z          == 90,  "MD_KEY_Z");
static_assert(MD_KEY_GRAVE      == 96,  "MD_KEY_GRAVE");
static_assert(MD_KEY_ESCAPE     == 256, "MD_KEY_ESCAPE");
static_assert(MD_KEY_UP         == 265, "MD_KEY_UP");
static_assert(MD_KEY_F1         == 290, "MD_KEY_F1");
static_assert(MD_KEY_F12        == 301, "MD_KEY_F12");
static_assert(MD_KEY_KP_0       == 320, "MD_KEY_KP_0");
static_assert(MD_KEY_KP_EQUAL   == 336, "MD_KEY_KP_EQUAL");
static_assert(MD_KEY_LEFT_SHIFT == 340, "MD_KEY_LEFT_SHIFT");
static_assert(MD_KEY_KB_MENU    == 348, "MD_KEY_KB_MENU");

// ---- Run-time: keyCode -> MD_KEY_* full table -----------------------------------------------
typedef struct { unsigned short code; int expect; const char *name; } Case;

static const Case kCases[] = {
    // Letters
    {0,MD_KEY_A,"A"},{11,MD_KEY_B,"B"},{8,MD_KEY_C,"C"},{2,MD_KEY_D,"D"},{14,MD_KEY_E,"E"},
    {3,MD_KEY_F,"F"},{5,MD_KEY_G,"G"},{4,MD_KEY_H,"H"},{34,MD_KEY_I,"I"},{38,MD_KEY_J,"J"},
    {40,MD_KEY_K,"K"},{37,MD_KEY_L,"L"},{46,MD_KEY_M,"M"},{45,MD_KEY_N,"N"},{31,MD_KEY_O,"O"},
    {35,MD_KEY_P,"P"},{12,MD_KEY_Q,"Q"},{15,MD_KEY_R,"R"},{1,MD_KEY_S,"S"},{17,MD_KEY_T,"T"},
    {32,MD_KEY_U,"U"},{9,MD_KEY_V,"V"},{13,MD_KEY_W,"W"},{7,MD_KEY_X,"X"},{16,MD_KEY_Y,"Y"},
    {6,MD_KEY_Z,"Z"},
    // Digits
    {29,MD_KEY_ZERO,"0"},{18,MD_KEY_ONE,"1"},{19,MD_KEY_TWO,"2"},{20,MD_KEY_THREE,"3"},
    {21,MD_KEY_FOUR,"4"},{23,MD_KEY_FIVE,"5"},{22,MD_KEY_SIX,"6"},{26,MD_KEY_SEVEN,"7"},
    {28,MD_KEY_EIGHT,"8"},{25,MD_KEY_NINE,"9"},
    // Punctuation
    {27,MD_KEY_MINUS,"MINUS"},{24,MD_KEY_EQUAL,"EQUAL"},{33,MD_KEY_LEFT_BRACKET,"LBRACKET"},
    {30,MD_KEY_RIGHT_BRACKET,"RBRACKET"},{42,MD_KEY_BACKSLASH,"BACKSLASH"},
    {41,MD_KEY_SEMICOLON,"SEMICOLON"},{39,MD_KEY_APOSTROPHE,"APOSTROPHE"},{50,MD_KEY_GRAVE,"GRAVE"},
    {43,MD_KEY_COMMA,"COMMA"},{47,MD_KEY_PERIOD,"PERIOD"},{44,MD_KEY_SLASH,"SLASH"},
    // Special / navigation
    {49,MD_KEY_SPACE,"SPACE"},{53,MD_KEY_ESCAPE,"ESCAPE"},{36,MD_KEY_ENTER,"ENTER"},
    {48,MD_KEY_TAB,"TAB"},{51,MD_KEY_BACKSPACE,"BACKSPACE"},{117,MD_KEY_DELETE,"DELETE"},
    {115,MD_KEY_HOME,"HOME"},{119,MD_KEY_END,"END"},{116,MD_KEY_PAGE_UP,"PAGE_UP"},
    {121,MD_KEY_PAGE_DOWN,"PAGE_DOWN"},{123,MD_KEY_LEFT,"LEFT"},{124,MD_KEY_RIGHT,"RIGHT"},
    {125,MD_KEY_DOWN,"DOWN"},{126,MD_KEY_UP,"UP"},{57,MD_KEY_CAPS_LOCK,"CAPS_LOCK"},
    // Function
    {122,MD_KEY_F1,"F1"},{120,MD_KEY_F2,"F2"},{99,MD_KEY_F3,"F3"},{118,MD_KEY_F4,"F4"},
    {96,MD_KEY_F5,"F5"},{97,MD_KEY_F6,"F6"},{98,MD_KEY_F7,"F7"},{100,MD_KEY_F8,"F8"},
    {101,MD_KEY_F9,"F9"},{109,MD_KEY_F10,"F10"},{103,MD_KEY_F11,"F11"},{111,MD_KEY_F12,"F12"},
    // Keypad
    {82,MD_KEY_KP_0,"KP_0"},{83,MD_KEY_KP_1,"KP_1"},{84,MD_KEY_KP_2,"KP_2"},{85,MD_KEY_KP_3,"KP_3"},
    {86,MD_KEY_KP_4,"KP_4"},{87,MD_KEY_KP_5,"KP_5"},{88,MD_KEY_KP_6,"KP_6"},{89,MD_KEY_KP_7,"KP_7"},
    {91,MD_KEY_KP_8,"KP_8"},{92,MD_KEY_KP_9,"KP_9"},{65,MD_KEY_KP_DECIMAL,"KP_DECIMAL"},
    {75,MD_KEY_KP_DIVIDE,"KP_DIVIDE"},{67,MD_KEY_KP_MULTIPLY,"KP_MULTIPLY"},
    {78,MD_KEY_KP_SUBTRACT,"KP_SUBTRACT"},{69,MD_KEY_KP_ADD,"KP_ADD"},{76,MD_KEY_KP_ENTER,"KP_ENTER"},
    {81,MD_KEY_KP_EQUAL,"KP_EQUAL"},
    // Modifiers
    {56,MD_KEY_LEFT_SHIFT,"LSHIFT"},{60,MD_KEY_RIGHT_SHIFT,"RSHIFT"},
    {59,MD_KEY_LEFT_CONTROL,"LCTRL"},{62,MD_KEY_RIGHT_CONTROL,"RCTRL"},
    {58,MD_KEY_LEFT_ALT,"LALT"},{61,MD_KEY_RIGHT_ALT,"RALT"},
    {55,MD_KEY_LEFT_SUPER,"LSUPER"},{54,MD_KEY_RIGHT_SUPER,"RSUPER"},
    // Unmapped codes must return MD_KEY_NULL (no Mac key, or fn)
    {114,MD_KEY_NULL,"(help/none)"},{63,MD_KEY_NULL,"(fn)"},{10,MD_KEY_NULL,"(unused)"},
    {200,MD_KEY_NULL,"(out-of-range)"},
};

int main(void)
{
    const int n = (int)(sizeof kCases / sizeof kCases[0]);
    int fails = 0;
    for (int i = 0; i < n; i++) {
        int got = md_MapKeyCode(kCases[i].code);
        if (got != kCases[i].expect) {
            printf("FAIL  keyCode %3u  %-14s  expected MD_KEY %d, got %d\n",
                   kCases[i].code, kCases[i].name, kCases[i].expect, got);
            fails++;
        }
    }
    printf("keymap test: %d/%d passed%s\n", n - fails, n, fails ? "  <-- FAILURES" : "");
    return fails ? 1 : 0;
}
