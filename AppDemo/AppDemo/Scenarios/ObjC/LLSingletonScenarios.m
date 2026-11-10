#import "LLSingletonScenarios.h"
#import "AppDemo-Swift.h"

@implementation LL47DashboardViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    L47Session.shared.activeScreen = self;
}

@end

@implementation LL48ScreenTracker

+ (LL48ScreenTracker *)sharedInstance {
    static LL48ScreenTracker *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [LL48ScreenTracker new]; });
    return shared;
}

@end

@implementation LL50ImageLoader {
    NSMutableDictionary<NSURL *, void (^)(UIImage *)> *_pending;
}

+ (LL50ImageLoader *)sharedInstance {
    static LL50ImageLoader *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [LL50ImageLoader new]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _pending = [NSMutableDictionary new];
    }
    return self;
}

- (void)loadImageWithURL:(NSURL *)url completion:(void (^)(UIImage *))completion {
    _pending[url] = [completion copy];
}

@end

@interface LL50AvatarViewController ()
@property (nonatomic, strong) UIImageView *avatarView;
@end

@implementation LL50AvatarViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.avatarView = [UIImageView new];
    [self.stack addArrangedSubview:self.avatarView];
    [LL50ImageLoader.sharedInstance loadImageWithURL:[NSURL URLWithString:@"https://example.com/l50.png"]
                                          completion:^(UIImage *image) {
        self.avatarView.image = image;
    }];
}

@end

@implementation LL52ListenerCenter {
    NSMutableArray *_listeners;
}

+ (LL52ListenerCenter *)sharedInstance {
    static LL52ListenerCenter *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [LL52ListenerCenter new]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _listeners = [NSMutableArray new];
    }
    return self;
}

- (void)addListener:(id)listener {
    [_listeners addObject:listener];
}

@end

@implementation LL52InboxViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [LL52ListenerCenter.sharedInstance addListener:self];
}

@end

@implementation LL53WeakListenerCenter {
    NSHashTable *_listeners;
}

+ (LL53WeakListenerCenter *)sharedInstance {
    static LL53WeakListenerCenter *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [LL53WeakListenerCenter new]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _listeners = [NSHashTable weakObjectsHashTable];
    }
    return self;
}

- (void)addListener:(id)listener {
    [_listeners addObject:listener];
}

@end

@implementation LL53WeakInboxViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [LL53WeakListenerCenter.sharedInstance addListener:self];
}

@end

@implementation LL55CachedGalleryViewController

+ (instancetype)cachedGallery {
    static LL55CachedGalleryViewController *cached;
    if (!cached) { cached = [[LL55CachedGalleryViewController alloc] initWithLogTag:@"L55"]; }
    return cached;
}

@end

@implementation LL56RetainedPlayerViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [L56MiniPlayerKeeper.shared keep:self];
}

@end
