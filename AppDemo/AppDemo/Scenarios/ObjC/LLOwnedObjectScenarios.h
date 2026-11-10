#import "LLTaggedObject.h"
#import "LLViewController.h"

NS_ASSUME_NONNULL_BEGIN

/// Owned by the Swift L30CheckoutViewController, kept forever by LL30SessionRegistry.
@interface LL30AnalyticsSession : LLTaggedObject
@end

@interface LL30SessionRegistry : NSObject
@property (class, nonatomic, readonly) LL30SessionRegistry *sharedInstance;
- (void)addSession:(LL30AnalyticsSession *)session;
@end

/// L31 — LEAK (outlived). ObjC self → Swift viewModel; L31CartStore.shared → viewModel.
@interface LL31CartViewController : LLViewController
@end

@interface LL32DraftStore : LLTaggedObject
@end

/// L32 — LEAK (outlived). ObjC self → draftStore; file-level static NSMutableArray → draftStore.
@interface LL32ComposeViewController : LLViewController
@end

/// A tree node whose `parent` is strong: parent ⇄ child.
@interface LL34Node : LLTaggedObject
@property (nonatomic, strong, nullable) LL34Node *parent;   // should be weak
@property (nonatomic, strong, readonly) NSMutableArray<LL34Node *> *children;
- (void)addChild:(LL34Node *)child;
@end

@class LL35DocumentController;

@interface LL35Document : LLTaggedObject
@property (nonatomic, strong, nullable) LL35DocumentController *controller;
@end

@interface LL35DocumentController : LLTaggedObject
@property (nonatomic, strong, nullable) LL35Document *document;   // should be weak
@end

/// L35 — LEAK (outlived, cycle). ObjC self → document ⇄ controller.
@interface LL35EditorViewController : LLViewController
@end

@class LL36File;

@interface LL36Folder : LLTaggedObject
@property (nonatomic, strong, readonly) NSMutableArray<LL36File *> *files;
- (void)addFile:(LL36File *)file;
@end

@interface LL36File : LLTaggedObject
@property (nonatomic, weak, nullable) LL36Folder *folder;
@end

/// Retains itself through its own block and registers with the instance budget.
@interface LL38SessionToken : LLTaggedObject
@property (nonatomic, copy, nullable) void (^onExpire)(void);
- (void)refresh;
@end

/// L38 — LEAK (budget). Creates a self-retaining LL38SessionToken it never stores.
@interface LL38LoginViewController : LLViewController
@end

/// L40 — LEAK (budget). Block cycle in a child whose container forgets willMove(toParent: nil).
@interface LL40CarelessChildViewController : LLViewController
@property (nonatomic, copy, nullable) void (^onUpdate)(void);
@end

NS_ASSUME_NONNULL_END
