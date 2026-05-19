// Stage R: Use dlsym'd _FBFeedUnitIsSponsored for clean ad detection
// No brute-force KVC. Call the actual predicate on feed items.

#include <UIKit/UIKit.h>
#include <objc/runtime.h>
#include <objc/message.h>
#include <string.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>

static IMP orig_viewDidAppear = NULL;
static BOOL glowButtonAttached = NO;
static id glowDatasourceRef = nil;
static BOOL methodEnumDone = NO;

typedef bool (*FBFeedUnitIsSponsoredFunc)(id feedUnit);
static FBFeedUnitIsSponsoredFunc isSponsoredFunc = NULL;

static void dumpSectionsFromState(id state, FILE *f) {
  Ivar sectionsIvar = class_getInstanceVariable(object_getClass(state), "_sections");
  if (!sectionsIvar) return;
  id sections = nil;
  @try { sections = object_getIvar(state, sectionsIvar); } @catch (...) {}
  if (!sections || ![sections isKindOfClass:[NSArray class]]) return;

  NSArray *sectionsArray = (NSArray *)sections;
  fprintf(f, "    _sections count: %lu\n", (unsigned long)sectionsArray.count);
  for (NSUInteger s = 0; s < sectionsArray.count; s++) {
    id section = sectionsArray[s];
    NSString *clsName = NSStringFromClass([section class]);
    fprintf(f, "    section[%lu]: %s\n", (unsigned long)s, clsName.UTF8String);
    if ([section isKindOfClass:[NSArray class]]) {
      NSArray *itemsArray = (NSArray *)section;
      fprintf(f, "      count: %lu\n", (unsigned long)itemsArray.count);
      for (NSUInteger j = 0; j < itemsArray.count && j < 30; j++) {
        id item = itemsArray[j];
        NSString *itemCls = NSStringFromClass([item class]);
        fprintf(f, "      [%lu] %s", (unsigned long)j, itemCls.UTF8String);

        if (isSponsoredFunc) {
          @try {
            bool sponsored = isSponsoredFunc(item);
            fprintf(f, " sponsored=%s", sponsored ? "YES" : "NO");
            if (sponsored) fprintf(f, " *** AD ***");
          } @catch (NSException *e) {
            fprintf(f, " EXCEPTION: %s", e.reason.UTF8String);
          } @catch (...) {
            fprintf(f, " EXCEPTION(c++)");
          }
        }

        @try {
          if ([item respondsToSelector:@selector(isSponsored)]) {
            id val = [item valueForKey:@"isSponsored"];
            fprintf(f, " isSponsored=%s", [val boolValue] ? "YES" : "NO");
          }
        } @catch (...) {}
        @try {
          if ([item respondsToSelector:@selector(sponsoredState)]) {
            id val = [item valueForKey:@"sponsoredState"];
            if (val) fprintf(f, " sponState=%s", NSStringFromClass([val class]).UTF8String);
          }
        } @catch (...) {}

        NSString *desc = [item respondsToSelector:@selector(description)] ? [item performSelector:@selector(description)] : nil;
        if (desc && [desc length] > 0 && [desc length] < 200) {
          fprintf(f, " desc=%s", desc.UTF8String);
        }
        fprintf(f, "\n");
      }
    }
  }
}

static void introspectDatasource(id datasource) {
  if (!datasource) return;
  const char *home = getenv("HOME");
  if (!home) return;

  char path[512];
  snprintf(path, sizeof(path), "%s/Documents/glow_feed.txt", home);
  FILE *f = fopen(path, "w");
  if (!f) return;

  fprintf(f, "=== Stage R: _FBFeedUnitIsSponsored dlsym ===\n");
  fprintf(f, "isSponsoredFunc: %s (%p)\n", isSponsoredFunc ? "YES" : "NO", (void*)isSponsoredFunc);

  Ivar tcdsIvar = class_getInstanceVariable(object_getClass(datasource), "_transactionalComponentDataSource");
  if (tcdsIvar) {
    id tcds = nil;
    @try { tcds = object_getIvar(datasource, tcdsIvar); } @catch (...) {}
    if (tcds) {
      Ivar dsIvar = class_getInstanceVariable(object_getClass(tcds), "_dataSource");
      if (dsIvar) {
        id ckds = nil;
        @try { ckds = object_getIvar(tcds, dsIvar); } @catch (...) {}
        if (ckds) {
          Ivar stateIvar = class_getInstanceVariable(object_getClass(ckds), "_state");
          if (stateIvar) {
            id state = nil;
            @try { state = object_getIvar(ckds, stateIvar); } @catch (...) {}
            if (state) {
              fprintf(f, "\n--- CKDataSourceState ---\n");
              dumpSectionsFromState(state, f);
            }
          }
        }
      }
    }
  }

  Ivar dsStateIvar = class_getInstanceVariable(object_getClass(datasource), "_dataSourceState");
  if (dsStateIvar) {
    id dsState = nil;
    @try { dsState = object_getIvar(datasource, dsStateIvar); } @catch (...) {}
    if (dsState) {
      fprintf(f, "\n--- Direct _dataSourceState ---\n");
      dumpSectionsFromState(dsState, f);
    }
  }

  fclose(f);
}

static void glowButtonTapped(id self, SEL _cmd, id sender) {
  if (glowDatasourceRef) introspectDatasource(glowDatasourceRef);
  const char *home = getenv("HOME");
  if (!home) return;
  char path[512];
  snprintf(path, sizeof(path), "%s/Documents/glow_tap.txt", home);
  FILE *f = fopen(path, "a");
  if (f) { fprintf(f, "TAP\n"); fclose(f); }
}

static void hooked_viewDidAppear(id self, SEL _cmd, BOOL animated) {
  if (orig_viewDidAppear)
    ((void(*)(id,SEL,BOOL))orig_viewDidAppear)(self, _cmd, animated);

  const char *className = class_getName(object_getClass(self));
  if (className && strstr(className, "FBNewsFeedViewController")) {
    UIViewController *vc = (UIViewController *)self;
    for (UIView *sub in vc.view.subviews) {
      NSString *subClassName = NSStringFromClass([sub class]);
      if ([subClassName containsString:@"FBNewsFeedCollectionView"] && [sub isKindOfClass:[UICollectionView class]]) {
        UICollectionView *cv = (UICollectionView *)sub;
        id ds = cv.dataSource;
        if (ds && !methodEnumDone) {
          methodEnumDone = YES;
          glowDatasourceRef = ds;
          dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            introspectDatasource(ds);
          });
        }
        break;
      }
    }
  }

  if (glowButtonAttached) return;
  UIViewController *vc = (UIViewController *)self;
  UIView *view = vc.view;
  if (!view || !vc.isViewLoaded || !view.window) return;
  UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
  button.frame = CGRectMake(0, 0, 60, 60);
  button.tag = 666666;
  button.backgroundColor = [UIColor blueColor];
  [button setTitle:@"GLOW" forState:UIControlStateNormal];
  class_addMethod([vc class], @selector(glowButtonTapped:), (IMP)glowButtonTapped, "v@:@");
  [button addTarget:vc action:@selector(glowButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
  [view addSubview:button];
  glowButtonAttached = YES;
}

__attribute__((constructor))
static void glow_init(void) {
  const char *home = getenv("HOME");
  if (!home) return;
  char path[512];
  snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
  FILE *f = fopen(path, "w");
  if (!f) return;
  fprintf(f, "Stage R: dlsym _FBFeedUnitIsSponsored\n\n");

  isSponsoredFunc = dlsym(RTLD_DEFAULT, "_FBFeedUnitIsSponsored");
  fprintf(f, "dlsym _FBFeedUnitIsSponsored: %p (%s)\n", (void*)isSponsoredFunc, isSponsoredFunc ? "OK" : dlerror());

  void *sponData = dlsym(RTLD_DEFAULT, "_FBSponsoredDataObjectsForFeedUnit");
  fprintf(f, "dlsym _FBSponsoredDataObjectsForFeedUnit: %p (%s)\n", sponData, sponData ? "OK" : dlerror());

  Class vcClass = objc_getClass("UIViewController");
  SEL vdaSel = @selector(viewDidAppear:);
  Method vdaM = class_getInstanceMethod(vcClass, vdaSel);
  if (vdaM) {
    orig_viewDidAppear = method_getImplementation(vdaM);
    method_setImplementation(vdaM, (IMP)hooked_viewDidAppear);
    fprintf(f, "HOOK: viewDidAppear:\n");
  }
  fclose(f);
}
