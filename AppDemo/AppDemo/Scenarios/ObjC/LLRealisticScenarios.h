#import "LLTaggedObject.h"
#import "LLViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class LL66FeedViewController;

@interface LL66FeedDataSource : LLTaggedObject <UITableViewDataSource>
@property (nonatomic, strong, nullable) LL66FeedViewController *owner;   // should be weak
@end

/// L66 — LEAK (cycle). self → dataSource → owner → self (UITableView.dataSource itself is weak).
@interface LL66FeedViewController : LLViewController
@end

/// L69 — LEAK (cycle). Old root of a navigation stack replaced by setViewControllers:. self → onRefresh → self.
@interface LL69LegacyRootViewController : LLViewController
@property (nonatomic, copy, nullable) void (^onRefresh)(void);
@end

/// L72 — LEAK (task). Starts a Swift Task ([weak screen]) on an endless stream; the Task outlives the screen.
@interface LL72LiveScoreViewController : LLViewController
- (void)showScore:(NSInteger)score;
@end

NS_ASSUME_NONNULL_END
