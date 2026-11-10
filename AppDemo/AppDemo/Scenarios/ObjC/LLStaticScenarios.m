#import "LLStaticScenarios.h"

static NSMutableArray<UIViewController *> *LL43RecentScreens;

@implementation LL43HistoryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    if (!LL43RecentScreens) { LL43RecentScreens = [NSMutableArray new]; }
    [LL43RecentScreens addObject:self];
}

@end

void LL44RememberScreen(UIViewController *screen) {
    static NSMutableDictionary<NSString *, UIViewController *> *screensByName;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ screensByName = [NSMutableDictionary new]; });
    screensByName[NSStringFromClass(screen.class)] = screen;
}

static UIViewController *LL45LastScreen;

@implementation LL45Navigator

+ (UIViewController *)lastScreen {
    return LL45LastScreen;
}

+ (void)setLastScreen:(UIViewController *)lastScreen {
    LL45LastScreen = lastScreen;
}

@end

@implementation LL45CheckoutViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    LL45Navigator.lastScreen = self;
}

@end
