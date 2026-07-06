#include "metaldraw.h"
#include <stdio.h>
#include <stdarg.h>
#include <atomic>

// Module-local state: the minimum level that actually prints. Default: show everything.
// _Atomic because TraceLog can run on a Metal background thread (the GPU-error completion
// handler) while the main thread may call SetTraceLogLevel.
static std::atomic<int> gLogLevel{MD_LOG_ALL};

void SetTraceLogLevel(int logLevel)
{
    gLogLevel = logLevel;   // atomic store
}

void TraceLog(int logLevel, const char *text, ...)
{
    if (text == NULL) return;                                       // NULL format is UB — reject
    if (logLevel <= MD_LOG_ALL || logLevel >= MD_LOG_NONE) return;  // only TRACE..FATAL are message levels
    if (logLevel < gLogLevel) return;                              // below the active threshold (atomic load)

    const char *tag;
    switch (logLevel) {
        case MD_LOG_TRACE:   tag = "TRACE";   break;
        case MD_LOG_DEBUG:   tag = "DEBUG";   break;
        case MD_LOG_INFO:    tag = "INFO";    break;
        case MD_LOG_WARNING: tag = "WARNING"; break;
        case MD_LOG_ERROR:   tag = "ERROR";   break;
        case MD_LOG_FATAL:   tag = "FATAL";   break;
        default:             tag = "LOG";     break;   // unreachable now (levels gated to 1..6)
    }

    // Format the whole line into one buffer, then emit with a SINGLE stdio call so
    // concurrent logs (e.g. the GPU-error handler on Metal's thread) can't interleave.
    char msg[512];
    va_list args;
    va_start(args, text);
    vsnprintf(msg, sizeof msg, text, args);
    va_end(args);

    printf("%s: %s\n", tag, msg);
}
