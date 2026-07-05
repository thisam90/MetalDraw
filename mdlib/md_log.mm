#include "metaldraw.h"
#include <stdio.h>
#include <stdarg.h>

// Module-local state: the minimum level that actually prints.
// static = private to this file. Default: show everything.
static int gLogLevel = MD_LOG_ALL;

void SetTraceLogLevel(int logLevel)
{
    gLogLevel = logLevel;
}

void TraceLog(int logLevel, const char *text, ...)
{
    if (logLevel < gLogLevel) return;

    const char *tag;
    switch (logLevel) {
        case MD_LOG_TRACE:   tag = "TRACE";   break;
        case MD_LOG_DEBUG:   tag = "DEBUG";   break;
        case MD_LOG_INFO:    tag = "INFO";    break;
        case MD_LOG_WARNING: tag = "WARNING"; break;
        case MD_LOG_ERROR:   tag = "ERROR";   break;
        case MD_LOG_FATAL:   tag = "FATAL";   break;
        default:             tag = "LOG";     break;
    }

    printf("%s: ", tag);

    va_list args;
    va_start(args, text);
    vprintf(text, args);
    va_end(args);

    printf("\n");
}