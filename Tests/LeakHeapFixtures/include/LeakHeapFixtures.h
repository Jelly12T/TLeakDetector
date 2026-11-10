//
//  LeakHeapFixtures.h
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Compiled with ARC, so clang emits the ivar layout and block extended layouts the reader relies on.
@interface LHFHolder : NSObject {
@public
    id _strongIvar;
    __weak id _weakIvar;
    __unsafe_unretained id _unretainedIvar;
    NSInteger _number;
    void (^_block)(void);
}
@property (nonatomic, strong, nullable) id strongProperty;
@property (nonatomic, weak, nullable) id weakProperty;
/// Set from Swift: the block is made by Swift from a closure.
@property (nonatomic, copy, nullable) void (^callback)(void);

- (void)setStrong:(nullable id)strong weak:(nullable id)weak unretained:(nullable id)unretained;
- (void)setBlockCapturingStrongly:(id)object;
- (void)setBlockCapturingWeakly:(id)object;
/// The block holds `object` through a `__block` variable: a byref, strong per its layout.
- (void)setBlockCapturingByref:(id)object;
@end

/// Only weak object ivars: no ivar layout at all.
@interface LHFWeakOnly : NSObject
@property (nonatomic, weak, nullable) id target;
@end

/// objc_setAssociatedObject called from Objective-C code.
void LHFAssociate(id owner, const void *key, id _Nullable value, BOOL retain);

NS_ASSUME_NONNULL_END
