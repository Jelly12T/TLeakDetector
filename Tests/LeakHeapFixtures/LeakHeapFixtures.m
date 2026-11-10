//
//  LeakHeapFixtures.m
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#import "LeakHeapFixtures.h"
#import <objc/runtime.h>

@implementation LHFHolder

- (void)setStrong:(id)strong weak:(id)weak unretained:(id)unretained {
    _strongIvar = strong;
    _weakIvar = weak;
    _unretainedIvar = unretained;
}

- (void)setBlockCapturingStrongly:(id)object {
    _block = ^{ (void)[object description]; };
}

- (void)setBlockCapturingWeakly:(id)object {
    __weak id weakObject = object;
    _block = ^{ (void)[weakObject description]; };
}

- (void)setBlockCapturingByref:(id)object {
    __block id shared = object;
    _block = ^{ shared = [shared description]; };
}

@end

@implementation LHFWeakOnly
@end

void LHFAssociate(id owner, const void *key, id value, BOOL retain) {
    objc_setAssociatedObject(owner, key, value, retain ? OBJC_ASSOCIATION_RETAIN_NONATOMIC : OBJC_ASSOCIATION_ASSIGN);
}
