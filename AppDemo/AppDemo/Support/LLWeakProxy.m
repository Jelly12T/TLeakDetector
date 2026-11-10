#import "LLWeakProxy.h"

@implementation LLWeakProxy

+ (instancetype)proxyWithTarget:(id)target {
    LLWeakProxy *proxy = [LLWeakProxy alloc];
    proxy->_target = target;
    return proxy;
}

- (id)forwardingTargetForSelector:(SEL)selector {
    return self.target;
}

// Reached only once the target is gone: swallow the message.
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    return [NSObject instanceMethodSignatureForSelector:@selector(init)];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    void *nothing = NULL;
    [invocation setReturnValue:&nothing];
}

@end
