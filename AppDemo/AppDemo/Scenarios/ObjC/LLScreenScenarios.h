#import "LLTaggedObject.h"
#import "LLViewController.h"

NS_ASSUME_NONNULL_BEGIN

/// L01 — LEAK (cycle). self → onRefresh → block → self.
@interface LL01BlockPropertyViewController : LLViewController
@property (nonatomic, copy, nullable) void (^onRefresh)(void);
@end

@class LL02Worker;
@protocol LL02WorkerDelegate <NSObject>
- (void)workerDidFinish:(LL02Worker *)worker;
@end

@interface LL02Worker : LLTaggedObject
@property (nonatomic, strong, nullable) id<LL02WorkerDelegate> delegate;   // should be weak
@end

/// L02 — LEAK (cycle). self → worker → delegate → self.
@interface LL02StrongDelegateViewController : LLViewController
@end

@class LL03Worker;
@protocol LL03WorkerDelegate <NSObject>
- (void)workerDidFinish:(LL03Worker *)worker;
@end

@interface LL03Worker : LLTaggedObject
@property (nonatomic, weak, nullable) id<LL03WorkerDelegate> delegate;
@end

/// L03 — NO LEAK. Like L02 with a weak delegate.
@interface LL03WeakDelegateViewController : LLViewController
@end

/// L04 — LEAK (rooted). RunLoop → NSTimer → target self. The timer property is weak, nobody invalidates.
@interface LL04TimerTargetViewController : LLViewController
@end

/// L05 — NO LEAK. NSTimer targets an LLWeakProxy, invalidated in dealloc.
@interface LL05WeakProxyTimerViewController : LLViewController
@end

/// L06 — LEAK (cycle, also rooted). self → observer token → block → self; NotificationCenter → token.
@interface LL06ObserverBlockViewController : LLViewController
@end

/// L07 — NO LEAK. Block observer with weakSelf, removed in dealloc.
@interface LL07ObserverRemovedViewController : LLViewController
@end

/// L08 — LEAK (subscription). Block observer with weakSelf, never removed: the screen dies, the observer stays.
@interface LL08ObserverNotRemovedViewController : LLViewController
@end

@interface LL09Settings : NSObject
@property (class, nonatomic, readonly) LL09Settings *sharedInstance;
@property (nonatomic, copy) NSString *theme;
@end

/// L09 — NO LEAK. KVO on a singleton, never removed: KVO does not retain the observer.
@interface LL09KVONotRemovedViewController : LLViewController
@end

/// L10 — NO LEAK, delayed release. dispatch_after 4 s captures self.
@interface LL10DispatchAfterViewController : LLViewController
@end

/// L11 — NO LEAK, late release. dispatch_after 15 s captures self, longer than T2.
@interface LL11LongDispatchAfterViewController : LLViewController
@end

/// L12 — NO LEAK. weakSelf/strongSelf dance in a block property.
@interface LL12WeakStrongDanceViewController : LLViewController
@property (nonatomic, copy, nullable) void (^onRefresh)(void);
@end

/// L13 — LEAK (cycle), suppressed in LeakSuppressions.json.
@interface LL13SuppressedLegacyViewController : LLViewController
@property (nonatomic, copy, nullable) void (^onRefresh)(void);
@end

NS_ASSUME_NONNULL_END
