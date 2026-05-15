#import <objc/runtime.h>
#import <dlfcn.h>
#import <UIKit/UIKit.h>

// Prefs
static NSString *const kP = @"/var/mobile/Library/Preferences/com.dvntm.glowprefs.plist";
static NSMutableDictionary *P;
#define PBOOL(k,d) [P[k] ?: @(d) boolValue]
static void loadP() { @autoreleasepool { P = [[NSMutableDictionary alloc] initWithContentsOfFile:kP]; if (!P) P = [NSMutableDictionary new]; } }

// Settings VC
@interface GlowVC : UITableViewController @end
@implementation GlowVC
- (id)init {
  self = [super initWithStyle:UITableViewStyleGrouped]; self.title = @"Glow";
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Close" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
  return self;
}
- (NSArray *)items { return @[
  @[@{@"h":@"Stories"}],
  @[@{@"k":@"AnonymousStories",@"l":@"Incognito Mode"}],
];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return [self items].count; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return [[self items][s][0][@"h"] isEqual:@"h"] ? 0 : [[self items][s] count]; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
  id d = [self items][p.section][p.row]; UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"c"];
  if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"c"];
  c.textLabel.text = d[@"l"]; c.selectionStyle = UITableViewCellSelectionStyleNone;
  UISwitch *sw = [[UISwitch alloc] init]; sw.on = PBOOL(d[@"k"], YES);
  sw.tag = p.section*100+p.row; [sw addTarget:self action:@selector(t:) forControlEvents:UIControlEventValueChanged];
  c.accessoryView = sw; return c;
}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { return [self items][s][0][@"h"]; }
- (void)t:(UISwitch *)s { id d = [self items][s.tag/100][s.tag%100]; P[d[@"k"]] = @(s.on); }
- (void)close { [P writeToFile:kP atomically:YES]; [self dismissViewControllerAnimated:YES completion:nil]; }
@end

// ─── Seen Fix ───
%group Seen
%hook FBSnacksUnifiedSeenStateMutator
- (void)_attemptSendSeenStateAndHandleResponse:(id)r bucket:(id)b { if (PBOOL(@"AnonymousStories", YES)) return; %orig; }
- (void)_markThreadsAsSeen:(id)t fromBucket:(id)b withTrackingString:(id)s isAnonymousView:(BOOL)a completion:(id)c { if (PBOOL(@"AnonymousStories", YES)) return; %orig; }
%end
%end

%ctor {
  @autoreleasepool {
    loadP();
    NSString *fw = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Frameworks/FBSharedFramework.framework/FBSharedFramework"];
    dlopen([fw UTF8String], RTLD_NOW | RTLD_GLOBAL);
    %init(Seen);
    NSLog(@"[Glow] stable build loaded");
  }
}
