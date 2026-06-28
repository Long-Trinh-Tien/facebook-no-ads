// UI/GlowSettingsViewController.m
#import "UI/GlowSettingsViewController.h"
#import "Managers/GlowSettingsManager.h"
#import "Managers/GlowLogManager.h"
#import "Utils/GlowCommon.h"

// Custom switch cell matching Glow design
@interface GlowSwitchCell : UITableViewCell
@property (nonatomic, strong) UISwitch *switchView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, copy) void (^onChangeBlock)(BOOL);
@end

@implementation GlowSwitchCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];

        self.switchView = [[UISwitch alloc] init];
        [self.switchView addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        self.accessoryView = self.switchView;

        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
        self.titleLabel.textColor = [UIColor labelColor];
        self.titleLabel.numberOfLines = 0;
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.titleLabel];

        self.subtitleLabel = [[UILabel alloc] init];
        self.subtitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        self.subtitleLabel.textColor = [UIColor secondaryLabelColor];
        self.subtitleLabel.numberOfLines = 0;
        self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:self.subtitleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [self.titleLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:10],
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            
            [self.subtitleLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:2],
            [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
            [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [self.subtitleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10]
        ]];
    }
    return self;
}

- (void)configureWithTitle:(NSString *)title subtitle:(NSString *)subtitle value:(BOOL)value onChange:(void (^)(BOOL))onChange {
    self.titleLabel.text = title;
    self.subtitleLabel.text = subtitle;
    self.switchView.on = value;
    self.onChangeBlock = onChange;
    
    if (subtitle.length == 0) {
        self.subtitleLabel.text = nil;
    }
}

- (void)switchChanged:(UISwitch *)sender {
    if (self.onChangeBlock) {
        self.onChangeBlock(sender.on);
    }
}
@end

@interface GlowSettingsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSArray<NSDictionary *> *> *sections;
@end

@implementation GlowSettingsViewController

- (instancetype)init {
    self = [super init];
    if (self) {
        GlowSettingsManager *sm = [GlowSettingsManager shared];
        _sections = @[
            @[  // HOME
                @{@"key": @"removeAds", @"title": @"removeAds", @"subtitle": @"", @"value": @(sm.removeAds)},
                @{@"key": @"removePYMK", @"title": @"removePYMK", @"subtitle": @"", @"value": @(sm.removePYMK)},
                @{@"key": @"removeReelsCarousel", @"title": @"removeReelsCarousel", @"subtitle": @"", @"value": @(sm.removeReelsCarousel)},
                @{@"key": @"removeSuggested", @"title": @"removeSuggested", @"subtitle": @"", @"value": @(sm.removeSuggested)},
                @{@"key": @"confirmLike", @"title": @"confirmLike", @"subtitle": @"", @"value": @(sm.confirmLike)},
                @{@"key": @"downloadVideo", @"title": @"downloadVideo", @"subtitle": @"downloadVideo.desc", @"value": @(sm.downloadVideo)},
            ],
            @[  // REELS
                @{@"key": @"downloadReels", @"title": @"downloadReels", @"subtitle": @"", @"value": @(sm.downloadReels)},
                @{@"key": @"hideOverlay", @"title": @"hideOverlay", @"subtitle": @"", @"value": @(sm.hideOverlay)},
                @{@"key": @"confirmReelsLike", @"title": @"confirmReelsLike", @"subtitle": @"", @"value": @(sm.confirmReelsLike)},
                @{@"key": @"downloadLongPress", @"title": @"downloadLongPress", @"subtitle": @"", @"value": @(sm.downloadLongPress)},
            ],
            @[  // STORIES
                @{@"key": @"downloadStory", @"title": @"downloadStory", @"subtitle": @"", @"value": @(sm.downloadStory)},
                @{@"key": @"disableStorySeen", @"title": @"disableStorySeen", @"subtitle": @"", @"value": @(sm.disableStorySeen)},
                @{@"key": @"disableAutoNext", @"title": @"disableAutoNext", @"subtitle": @"", @"value": @(sm.disableAutoNext)},
                @{@"key": @"removeStoryPYMK", @"title": @"removeStoryPYMK", @"subtitle": @"", @"value": @(sm.removeStoryPYMK)},
            ],
            @[  // DOWNLOADER
                @{@"key": @"allFormats", @"title": @"allFormats", @"subtitle": @"", @"value": @(sm.allFormats)},
            ],
            @[  // OTHER
                @{@"key": @"notifyUpdates", @"title": @"notifyUpdates", @"subtitle": @"", @"value": @(sm.notifyUpdates)},
                @{@"key": @"clearCacheOnLaunch", @"title": @"clearCacheOnLaunch", @"subtitle": @"", @"value": @(sm.clearCacheOnLaunch)},
            ],
        ];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.title = @"Glow Settings";

    // Grabber for sheet style presentation
    if (@available(iOS 15.0, *)) {
        self.sheetPresentationController.prefersGrabberVisible = YES;
    }

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemClose
        target:self
        action:@selector(closeSettings)];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    [self.tableView registerClass:[GlowSwitchCell class] forCellReuseIdentifier:@"switch"];
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)closeSettings {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.sections[section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSArray *keys = @[@"section.home", @"section.reels", @"section.stories", @"section.downloader", @"section.other"];
    if (section >= (NSInteger)keys.count) return nil;
    return [GlowSettingsManager localizedString:keys[section]];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    GlowSwitchCell *cell = [tableView dequeueReusableCellWithIdentifier:@"switch" forIndexPath:indexPath];
    NSDictionary *row = self.sections[indexPath.section][indexPath.row];
    NSString *title = [GlowSettingsManager localizedString:row[@"title"]];
    NSString *subtitleKey = row[@"subtitle"];
    NSString *subtitle = subtitleKey.length > 0 ? [GlowSettingsManager localizedString:subtitleKey] : @"";
    BOOL value = [row[@"value"] boolValue];
    NSString *key = row[@"key"];

    [cell configureWithTitle:title subtitle:subtitle value:value onChange:^(BOOL newValue) {
        NSString *fullKey = [@"com.tommy.glow." stringByAppendingString:key];
        [[NSUserDefaults standardUserDefaults] setBool:newValue forKey:fullKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [[GlowSettingsManager shared] loadSettings];
        LOG("[settings] %s = %d\n", key.UTF8String, newValue);
    }];
    return cell;
}

@end
