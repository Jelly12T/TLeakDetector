#import "LLCrossLanguageScenarios.h"
#import "AppDemo-Swift.h"

// The cycles in this file are the scenarios under test.
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@interface LL14ProfileViewController ()
@property (nonatomic, strong) L14ProfileViewModel *viewModel;
@end

@implementation LL14ProfileViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.viewModel = [[L14ProfileViewModel alloc] initWithLogTag:@"L14.viewModel"];
    self.viewModel.onChange = ^{
        [self render];
    };
}

- (void)render {}

@end

@implementation LL15Downloader
@end

@implementation LL16Uploader
@end

@interface LL17SyncViewController () <L17SyncerDelegate>
@property (nonatomic, strong) L17Syncer *syncer;
@end

@implementation LL17SyncViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.syncer = [[L17Syncer alloc] initWithLogTag:@"L17.syncer"];
    self.syncer.delegate = self;
}

- (void)syncerDidFinish {}

@end

@implementation LL18ThumbnailFetcher
@end

@interface LL19SettingsViewController ()
@property (nonatomic, strong) L19SettingsViewModel *viewModel;
@end

@implementation LL19SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.viewModel = [[L19SettingsViewModel alloc] initWithLogTag:@"L19.viewModel"];
    __weak typeof(self) weakSelf = self;
    self.viewModel.onChange = ^{
        [weakSelf render];
    };
}

- (void)render {}

@end
