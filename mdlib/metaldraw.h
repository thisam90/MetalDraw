#ifndef METALDRAW_H
#define METALDRAW_H
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

void InitWindow(int width, int height, const char* title);
bool WindowShouldClose(void);
void CloseWindow(void);

#ifdef __cplusplus
}
#endif


#endif // METALDRAW_H
