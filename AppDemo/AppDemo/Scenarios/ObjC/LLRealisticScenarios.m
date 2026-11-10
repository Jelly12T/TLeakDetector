#import "LLRealisticScenarios.h"
#import "AppDemo-Swift.h"

// The cycles in this file are the scenarios under test.
#pragma clang diagnostic ignored "-Warc-retain-cycles"

@implementation LL66FeedDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 3;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    cell.textLabel.text = [NSString stringWithFormat:@"Post %ld", (long)indexPath.row];
    return cell;
}

@end

@interface LL66FeedViewController ()
@property (nonatomic, strong) LL66FeedDataSource *dataSource;
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation LL66FeedViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.dataSource = [[LL66FeedDataSource alloc] initWithLogTag:@"L66.dataSource"];
    self.dataSource.owner = self;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 320, 300) style:UITableViewStylePlain];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"cell"];
    self.tableView.dataSource = self.dataSource;
    [self.stack addArrangedSubview:self.tableView];
    [self.tableView.heightAnchor constraintEqualToConstant:300].active = YES;
    [self.tableView.widthAnchor constraintEqualToConstant:320].active = YES;
}

@end

@implementation LL69LegacyRootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.onRefresh = ^{
        [self reload];
    };
}

- (void)reload {}

@end

@implementation LL72LiveScoreViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [L72ScoreFeed listenForScreen:self];
}

- (void)showScore:(NSInteger)score {}

@end
