#import "LLViewController.h"
#import "LLLog.h"

@implementation LLViewController

- (instancetype)initWithLogTag:(NSString *)logTag {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _logTag = [logTag copy];
        _stack = [UIStackView new];
    }
    return self;
}

- (void)dealloc {
    LLLog(@"deinit %@", _logTag);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.view.accessibilityIdentifier = [@"lab.screen." stringByAppendingString:self.logTag];

    UILabel *label = [UILabel new];
    label.text = self.title ? [NSString stringWithFormat:@"%@\n%@ (Objective-C)", self.title, self.logTag]
                            : self.logTag;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;

    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 16;
    self.stack.alignment = UIStackViewAlignmentCenter;
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.stack addArrangedSubview:label];
    [self.view addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[
        [self.stack.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerYAnchor],
        [self.stack.leadingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.leadingAnchor],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor],
    ]];

    if (self.showsCloseButton) {
        __weak typeof(self) weakSelf = self;
        [self addButtonWithTitle:@"Close" identifier:@"lab.close" handler:^{
            [weakSelf dismissViewControllerAnimated:YES completion:nil];
        }];
    }
}

- (void)addButtonWithTitle:(NSString *)title identifier:(NSString *)identifier handler:(void (^)(void))handler {
    UIAction *action = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(__kindof UIAction *_) {
        handler();
    }];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem primaryAction:action];
    button.accessibilityIdentifier = identifier;
    [self.stack addArrangedSubview:button];
}

@end
