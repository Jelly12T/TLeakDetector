#import "LLViewController.h"

NS_ASSUME_NONNULL_BEGIN

/// L47 — LEAK (rooted). Swift singleton L47Session.shared.activeScreen → ObjC self.
@interface LL47DashboardViewController : LLViewController
@end

/// Holds the current screen strongly. Used by the Swift L48 screen.
@interface LL48ScreenTracker : NSObject
@property (class, nonatomic, readonly) LL48ScreenTracker *sharedInstance;
@property (nonatomic, strong, nullable) UIViewController *currentScreen;
@end

/// Keeps every completion until its request finishes; this one never does.
@interface LL50ImageLoader : NSObject
@property (class, nonatomic, readonly) LL50ImageLoader *sharedInstance;
- (void)loadImageWithURL:(NSURL *)url completion:(void (^)(UIImage *_Nullable image))completion;
@end

/// L50 — LEAK (rooted). LL50ImageLoader.sharedInstance → pending completion block → self.
@interface LL50AvatarViewController : LLViewController
@end

@interface LL52ListenerCenter : NSObject
@property (class, nonatomic, readonly) LL52ListenerCenter *sharedInstance;
- (void)addListener:(id)listener;
@end

/// L52 — LEAK (rooted). ObjC singleton strong NSMutableArray of listeners → self, never removed.
@interface LL52InboxViewController : LLViewController
@end

@interface LL53WeakListenerCenter : NSObject
@property (class, nonatomic, readonly) LL53WeakListenerCenter *sharedInstance;
- (void)addListener:(id)listener;
@end

/// L53 — NO LEAK. Like L52 with an NSHashTable of weak objects.
@interface LL53WeakInboxViewController : LLViewController
@end

/// L55 — ALLOWED. Cached by LL55ScreenCache on purpose and listed in `allowedTypes`.
@interface LL55CachedGalleryViewController : LLViewController
+ (instancetype)cachedGallery;
@end

/// L56 — ALLOWED. Kept by the Swift L56MiniPlayerKeeper on purpose; conforms to LeakOptOut in Swift.
@interface LL56RetainedPlayerViewController : LLViewController
@end

NS_ASSUME_NONNULL_END
