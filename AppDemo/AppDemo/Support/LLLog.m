#import "LLLog.h"

void LLLogMessage(NSString *message) {
    printf("[AppDemo] t=%.3f %s\n", NSProcessInfo.processInfo.systemUptime, message.UTF8String);
    fflush(stdout);
}
