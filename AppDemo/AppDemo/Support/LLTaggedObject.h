#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Base class of the Objective-C (and @objc Swift) non-screen objects: logs its dealloc.
@interface LLTaggedObject : NSObject
@property (nonatomic, copy, readonly) NSString *logTag;
- (instancetype)initWithLogTag:(NSString *)logTag NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
