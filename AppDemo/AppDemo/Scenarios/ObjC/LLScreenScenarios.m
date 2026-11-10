#import "LLScreenScenarios.h"
#import "LLWeakProxy.h"

// The cycles in this file are the scenarios under test.
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@implementation LL01BlockPropertyViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.onRefresh = ^{
        [self reload];
    };
}

- (void)reload {}

@end

@implementation LL02Worker
@end

@interface LL02StrongDelegateViewController () <LL02WorkerDelegate>
@property (nonatomic, strong) LL02Worker *worker;
@end

@implementation LL02StrongDelegateViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.worker = [[LL02Worker alloc] initWithLogTag:@"L02.worker"];
    self.worker.delegate = self;
}

- (void)workerDidFinish:(LL02Worker *)worker {}

@end

@implementation LL03Worker
@end

@interface LL03WeakDelegateViewController () <LL03WorkerDelegate>
@property (nonatomic, strong) LL03Worker *worker;
@end

@implementation LL03WeakDelegateViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.worker = [[LL03Worker alloc] initWithLogTag:@"L03.worker"];
    self.worker.delegate = self;
}

- (void)workerDidFinish:(LL03Worker *)worker {}

@end

@interface LL04TimerTargetViewController ()
@property (nonatomic, weak) NSTimer *timer;
@end

@implementation LL04TimerTargetViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(tick) userInfo:nil repeats:YES];
}

- (void)tick {}

@end

@interface LL05WeakProxyTimerViewController ()
@property (nonatomic, weak) NSTimer *timer;
@end

@implementation LL05WeakProxyTimerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1
                                                  target:[LLWeakProxy proxyWithTarget:self]
                                                selector:@selector(tick)
                                                userInfo:nil
                                                 repeats:YES];
}

- (void)dealloc {
    [_timer invalidate];
}

- (void)tick {}

@end

@interface LL06ObserverBlockViewController ()
@property (nonatomic, strong) id<NSObject> observer;
@end

@implementation LL06ObserverBlockViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.observer = [NSNotificationCenter.defaultCenter addObserverForName:@"LL06Ping"
                                                                    object:nil
                                                                     queue:NSOperationQueue.mainQueue
                                                                usingBlock:^(NSNotification *note) {
        [self reload];
    }];
}

- (void)reload {}

@end

@interface LL07ObserverRemovedViewController ()
@property (nonatomic, strong) id<NSObject> observer;
@end

@implementation LL07ObserverRemovedViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    __weak typeof(self) weakSelf = self;
    self.observer = [NSNotificationCenter.defaultCenter addObserverForName:@"LL07Ping"
                                                                    object:nil
                                                                     queue:NSOperationQueue.mainQueue
                                                                usingBlock:^(NSNotification *note) {
        [weakSelf reload];
    }];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:_observer];
}

- (void)reload {}

@end

@implementation LL08ObserverNotRemovedViewController {
    id<NSObject> _observer;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    __weak typeof(self) weakSelf = self;
    _observer = [NSNotificationCenter.defaultCenter addObserverForName:@"LL08Ping"
                                                                object:nil
                                                                 queue:NSOperationQueue.mainQueue
                                                            usingBlock:^(NSNotification *note) {
        [weakSelf reload];
    }];
}

- (void)reload {}

@end

@implementation LL09Settings

+ (LL09Settings *)sharedInstance {
    static LL09Settings *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [LL09Settings new]; });
    return shared;
}

@end

static void *LL09ThemeContext = &LL09ThemeContext;

@implementation LL09KVONotRemovedViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [LL09Settings.sharedInstance addObserver:self forKeyPath:@"theme" options:0 context:LL09ThemeContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
    if (context != LL09ThemeContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

@end

@implementation LL10DispatchAfterViewController

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self flush];
    });
}

- (void)flush {}

@end

@implementation LL11LongDispatchAfterViewController

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self flush];
    });
}

- (void)flush {}

@end

@implementation LL12WeakStrongDanceViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    __weak typeof(self) weakSelf = self;
    self.onRefresh = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { return; }
        [strongSelf reload];
    };
}

- (void)reload {}

@end

@implementation LL13SuppressedLegacyViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.onRefresh = ^{
        [self reload];
    };
}

- (void)reload {}

@end
