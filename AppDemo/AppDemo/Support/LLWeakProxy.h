#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Forwards messages to a target it holds weakly: a timer target that does not keep the screen alive.
@interface LLWeakProxy : NSProxy
@property (nonatomic, weak, readonly, nullable) id target;
+ (instancetype)proxyWithTarget:(id)target;
@end

NS_ASSUME_NONNULL_END
