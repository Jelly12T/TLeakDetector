#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A screen that takes more than one step to close (child hosts, root replacements).
/// Buttons call it, and so does the autorun.
@protocol LLStepping <NSObject>
- (void)performNextStepAnimated:(BOOL)animated;
@end

/// What the router needs from any Lab screen, Swift or Objective-C.
@protocol LLScreen <NSObject>
@property (nonatomic) BOOL showsCloseButton;
@end

/// Base class of every Objective-C Lab screen: logs its dealloc, shows a label and buttons.
/// It must not create or break any reference cycle itself.
@interface LLViewController : UIViewController <LLScreen>

@property (nonatomic, copy, readonly) NSString *logTag;
@property (nonatomic) BOOL showsCloseButton;
@property (nonatomic, strong, readonly) UIStackView *stack;

- (instancetype)initWithLogTag:(NSString *)logTag NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

/// `handler` must not capture `self` strongly.
- (void)addButtonWithTitle:(NSString *)title identifier:(NSString *)identifier handler:(void (^)(void))handler;

@end

NS_ASSUME_NONNULL_END
