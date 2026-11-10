#import "LLViewController.h"

NS_ASSUME_NONNULL_BEGIN

/// L43 — LEAK (rooted). File-level `static NSMutableArray *` → self.
@interface LL43HistoryViewController : LLViewController
@end

/// Keeps `screen` in a function-local static dictionary, keyed by class name. Used by the Swift L44 screen.
FOUNDATION_EXPORT void LL44RememberScreen(UIViewController *screen);

@interface LL45Navigator : NSObject
@property (class, nonatomic, strong, nullable) UIViewController *lastScreen;
@end

/// L45 — LEAK (rooted). Class property backed by a static: LL45Navigator.lastScreen → self.
@interface LL45CheckoutViewController : LLViewController
@end

NS_ASSUME_NONNULL_END
