#import "LLOwnedObjectScenarios.h"
#import "AppDemo-Swift.h"

// The cycles in this file are the scenarios under test.
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@implementation LL30AnalyticsSession
@end

@implementation LL30SessionRegistry {
    NSMutableArray<LL30AnalyticsSession *> *_sessions;
}

+ (LL30SessionRegistry *)sharedInstance {
    static LL30SessionRegistry *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [LL30SessionRegistry new]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _sessions = [NSMutableArray new];
    }
    return self;
}

- (void)addSession:(LL30AnalyticsSession *)session {
    [_sessions addObject:session];
}

@end

@interface LL31CartViewController ()
@property (nonatomic, strong) L31CartViewModel *viewModel;
@end

@implementation LL31CartViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.viewModel = [[L31CartViewModel alloc] initWithLogTag:@"L31.viewModel"];
    [L31CartStore.shared attach:self.viewModel];
}

@end

@implementation LL32DraftStore
@end

static NSMutableArray<LL32DraftStore *> *LL32PendingDrafts;

@interface LL32ComposeViewController ()
@property (nonatomic, strong) LL32DraftStore *draftStore;
@end

@implementation LL32ComposeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.draftStore = [[LL32DraftStore alloc] initWithLogTag:@"L32.draftStore"];
    if (!LL32PendingDrafts) { LL32PendingDrafts = [NSMutableArray new]; }
    [LL32PendingDrafts addObject:self.draftStore];
}

@end

@implementation LL34Node

- (instancetype)initWithLogTag:(NSString *)logTag {
    self = [super initWithLogTag:logTag];
    if (self) {
        _children = [NSMutableArray new];
    }
    return self;
}

- (void)addChild:(LL34Node *)child {
    child.parent = self;
    [_children addObject:child];
}

@end

@implementation LL35Document
@end

@implementation LL35DocumentController
@end

@interface LL35EditorViewController ()
@property (nonatomic, strong) LL35Document *document;
@end

@implementation LL35EditorViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    LL35Document *document = [[LL35Document alloc] initWithLogTag:@"L35.document"];
    LL35DocumentController *controller = [[LL35DocumentController alloc] initWithLogTag:@"L35.controller"];
    document.controller = controller;
    controller.document = document;
    self.document = document;
}

@end

@implementation LL36Folder

- (instancetype)initWithLogTag:(NSString *)logTag {
    self = [super initWithLogTag:logTag];
    if (self) {
        _files = [NSMutableArray new];
    }
    return self;
}

- (void)addFile:(LL36File *)file {
    file.folder = self;
    [_files addObject:file];
}

@end

@implementation LL36File
@end

@implementation LL38SessionToken

- (instancetype)initWithLogTag:(NSString *)logTag {
    self = [super initWithLogTag:logTag];
    if (self) {
        self.onExpire = ^{
            [self refresh];
        };
#if DEBUG
        [LabLeakTracking track:self];
#endif
    }
    return self;
}

- (void)refresh {}

@end

@implementation LL38LoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    LL38SessionToken *token = [[LL38SessionToken alloc] initWithLogTag:@"L38.token"];
    [token refresh];
}

@end

@implementation LL40CarelessChildViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.onUpdate = ^{
        [self reload];
    };
}

- (void)reload {}

@end
