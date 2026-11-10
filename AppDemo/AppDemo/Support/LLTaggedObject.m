#import "LLTaggedObject.h"
#import "LLLog.h"

@implementation LLTaggedObject

- (instancetype)initWithLogTag:(NSString *)logTag {
    self = [super init];
    if (self) {
        _logTag = [logTag copy];
    }
    return self;
}

- (void)dealloc {
    LLLog(@"deinit %@", _logTag);
}

@end
