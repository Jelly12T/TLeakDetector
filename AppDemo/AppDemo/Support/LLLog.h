#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Prints `[AppDemo] t=<uptime> <message>` to stdout. Safe to call from dealloc.
FOUNDATION_EXPORT void LLLogMessage(NSString *message);

#define LLLog(format, ...) LLLogMessage([NSString stringWithFormat:(format), ##__VA_ARGS__])

NS_ASSUME_NONNULL_END
