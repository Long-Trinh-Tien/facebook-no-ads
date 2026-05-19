// Stage Q: Periodic feed dump + CKDataSource state hook + attachController scope dump
// Retry at 3s, 10s, 20s to catch feed after load
// Try hooking CKDataSource's setState: if available
// Dump scopeIdentifierToAttachedViewMap from attachController

#include <UIKit/UIKit.h>
#include <objc/runtime.h>
#include <objc/message.h>
#include <string.h>
#include <dispatch/dispatch.h>

static IMP orig_viewDidAppear = NULL;
static BOOL glowButtonAttached = NO;
static const NSInteger kGlowButtonTag = 666666;
static id glowDatasourceRef = nil;
static BOOL methodEnumDone = NO;
static int retryCount = 0;
static BOOL feedDumped = NO;

// Forward declarations
static void dumpSectionItems(id section, FILE *f, int indent);
static void dumpSectionsFromState(id state, FILE *f);
static void dumpItemProperties(id item, FILE *f, const char *ind, int depth);
static void introspectDatasource(id datasource);
static void scheduleRetry(id datasource);

// Log all methods on a class
static void logClassMethods(Class cls, FILE *f) {
  unsigned int count = 0;
  Method *methods = class_copyMethodList(cls, &count);
  if (methods) {
    for (unsigned int i = 0; i < count; i++) {
      SEL sel = method_getName(methods[i]);
      const char *name = sel_getName(sel);
      const char *types = method_getTypeEncoding(methods[i]);
      fprintf(f, "  %s (%s)\n", name, types);
    }
    free(methods);
  }
}

// Try to get an object from datasource at index path
static id tryDatasourceMethod(id datasource, SEL sel, NSIndexPath *indexPath, FILE *f) {
  @try {
    unsigned int argCount = method_getNumberOfArguments(class_getInstanceMethod(object_getClass(datasource), sel));
    if (argCount == 3) {
      // Method takes (id self, SEL _cmd, NSIndexPath *)
      id result = ((id(*)(id,SEL,NSIndexPath *))objc_msgSend)(datasource, sel, indexPath);
      if (result && [result isKindOfClass:[NSObject class]]) {
        fprintf(f, "  %s -> %s (%p)\n", sel_getName(sel), NSStringFromClass([result class]).UTF8String, (__bridge void *)result);

        // Log interesting properties
        @try {
          if ([result respondsToSelector:@selector(description)]) {
            NSString *desc = [result performSelector:@selector(description)];
            if (desc && [desc length] > 0 && [desc length] < 500) {
              BOOL hasSponsored = [desc containsString:@"Sponsored"] || [desc containsString:@"sponsored"] ||
                                   [desc containsString:@"AdUnit"] || [desc containsString:@"Promoted"] ||
                                   [desc containsString:@"feedUnit"] || [desc containsString:@"isSponsored"] ||
                                   [desc containsString:@"sponsoredState"] || [desc containsString:@"AdData"];
              if (hasSponsored) {
                fprintf(f, "    *** %s\n", desc.UTF8String);
              }
            }
          }
        } @catch (...) {}

        // Check for sponsored-related KVC properties
        const char *props[] = {
          "isSponsored", "sponsoredState", "sponsoredData", "adData", "adModel",
          "feedUnitType", "unitType", "story", "attachment", "model",
          "actor", "title", "body", "content", "data"
        };
        for (int i = 0; i < (int)(sizeof(props)/sizeof(props[0])); i++) {
          @try {
            NSString *key = [NSString stringWithUTF8String:props[i]];
            if ([result respondsToSelector:NSSelectorFromString(key)]) {
              id val = [result valueForKey:key];
              if (val) {
                if ([val isKindOfClass:[NSString class]]) {
                  fprintf(f, "    %s: '%s'\n", props[i], ((NSString *)val).UTF8String);
                } else {
                  fprintf(f, "    %s: %s\n", props[i], NSStringFromClass([val class]).UTF8String);
                }
              }
            }
          } @catch (...) {}
        }

        return result;
      }
    }
  } @catch (...) {}
  return nil;
}

// Dump items from a CKDataSourceState
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
      // Section IS an array of items directly
      NSArray *itemsArray = (NSArray *)section;
      fprintf(f, "      (NSArray) count: %lu\n", (unsigned long)itemsArray.count);
      for (NSUInteger j = 0; j < itemsArray.count && j < 15; j++) {
        id item = itemsArray[j];
        fprintf(f, "      item[%lu]: %s\n", (unsigned long)j, NSStringFromClass([item class]).UTF8String);
        dumpItemProperties(item, f, "      ", 2);
      }
    } else {
      // Fallback: try _items ivar
      dumpSectionItems(section, f, 2);
    }
  }
  if (sectionsArray.count > 0) feedDumped = YES;
}

// Dump items from a section (which is actually an NSArray of items)
static void dumpSectionItems(id section, FILE *f, int indent) {
  const char *ind = (indent == 1) ? "      " : "        ";
  id items = section;
  // The "section" IS an NSArray subclass directly containing items
  if (!items || ![items isKindOfClass:[NSArray class]]) {
    // Fallback: try _items ivar
    Ivar itemsIvar = class_getInstanceVariable(object_getClass(section), "_items");
    if (!itemsIvar) itemsIvar = class_getInstanceVariable(object_getClass(section), "items");
    if (!itemsIvar) itemsIvar = class_getInstanceVariable(object_getClass(section), "_objects");
    if (itemsIvar) @try { items = object_getIvar(section, itemsIvar); } @catch (...) {}
    if (!items || ![items isKindOfClass:[NSArray class]]) {
      // Maybe it has a single item ivar
      Ivar objIvar = class_getInstanceVariable(object_getClass(section), "_object");
      if (objIvar) {
        id obj = nil;
        @try { obj = object_getIvar(section, objIvar); } @catch (...) {}
        if (obj) {
          fprintf(f, "%s_singleObject: %s\n", ind, NSStringFromClass([obj class]).UTF8String);
          dumpItemProperties(obj, f, ind, 2);
        }
      }
      return;
    }
  }

  NSArray *itemsArray = (NSArray *)items;
  fprintf(f, "%sitems count: %lu\n", ind, (unsigned long)itemsArray.count);
  for (NSUInteger j = 0; j < itemsArray.count && j < 20; j++) {
    id item = itemsArray[j];
    fprintf(f, "%sitem[%lu]: %s\n", ind, (unsigned long)j, NSStringFromClass([item class]).UTF8String);
    dumpItemProperties(item, f, ind, 2);
  }
}

// Dump properties of a single feed item
static void dumpItemProperties(id item, FILE *f, const char *ind, int depth) {
  if (depth > 4) return;

  // Description check
  @try {
    if ([item respondsToSelector:@selector(description)]) {
      NSString *desc = [item performSelector:@selector(description)];
      if (desc && [desc length] > 0 && [desc length] < 600) {
        BOOL hasSpon = [desc containsString:@"Sponsored"] || [desc containsString:@"AdUnit"] ||
                       [desc containsString:@"feedUnit"] || [desc containsString:@"isSponsored"] ||
                       [desc containsString:@"promoted"] || [desc containsString:@"Promoted"] ||
                       [desc containsString:@"adData"] || [desc containsString:@"sponsor"];
        if (hasSpon) fprintf(f, "%s*** SPONSORED: %s\n", ind, desc.UTF8String);
        else fprintf(f, "%sdesc: %s\n", ind, desc.UTF8String);
      }
    }
  } @catch (...) {}

  // KVC on item
  const char *props[] = {"isSponsored", "sponsoredState", "sponsoredData", "adData",
    "feedUnitType", "unitType", "story", "attachment", "model", "actor",
    "title", "body", "content", "data", "sponsoredLabel", "promotedState",
    "sponsoredImpression", "adProperties", "tracking", "sponsoredInfo",
    "feedStory", "feedUnit", "unit", "adPropertiesData", "sponsor",
    "sponsoredCandidate", "sponsoredImpressionInfo", "adAttribution"};
  for (int k = 0; k < (int)(sizeof(props)/sizeof(props[0])); k++) {
    @try {
      NSString *key = [NSString stringWithUTF8String:props[k]];
      if ([item respondsToSelector:NSSelectorFromString(key)]) {
        id val2 = [item valueForKey:key];
        if (val2) {
          if ([val2 isKindOfClass:[NSString class]]) {
            fprintf(f, "%s  %s: '%s'\n", ind, props[k], ((NSString *)val2).UTF8String);
          } else {
            fprintf(f, "%s  %s: %s\n", ind, props[k], NSStringFromClass([val2 class]).UTF8String);
            if (depth < 4 && [val2 isKindOfClass:[NSArray class]] && [(NSArray *)val2 count] > 0 && [(NSArray *)val2 count] <= 5) {
              for (id subItem in (NSArray *)val2) {
                dumpItemProperties(subItem, f, ind, depth + 1);
              }
            } else if (depth < 4 && [val2 isKindOfClass:[NSArray class]] && [(NSArray *)val2 count] > 5) {
              fprintf(f, "%s    [%lu items - truncated]\n", ind, (unsigned long)[(NSArray *)val2 count]);
            }
          }
        }
      }
    } @catch (...) {}
  }

  // Enumerate all ivars for ObjC objects (depth-limited)
  if (depth < 3) {
    unsigned int ivarCount = 0;
    Ivar *ivars = class_copyIvarList(object_getClass(item), &ivarCount);
    for (unsigned int i = 0; i < ivarCount && i < 60; i++) {
      const char *name = ivar_getName(ivars[i]);
      const char *enc = ivar_getTypeEncoding(ivars[i]);
      if (enc[0] == '@') { // ObjC object type
        id val = nil;
        @try { val = object_getIvar(item, ivars[i]); } @catch (...) {}
        if (val && [val isKindOfClass:[NSObject class]] && val != item) {
          // Check if name or class suggests sponsored content
          if (strstr(name, "sponsor") || strstr(name, "ad") || strstr(name, "Ad") ||
              strstr(name, "promot") || strstr(name, "Promot") ||
              [NSStringFromClass([val class]) containsString:@"Sponsor"] ||
              [NSStringFromClass([val class]) containsString:@"Ad"]) {
            fprintf(f, "%s  ivar %s -> %s\n", ind, name, NSStringFromClass([val class]).UTF8String);
            if (depth < 3) dumpItemProperties(val, f, ind, depth + 1);
          }
        }
      }
    }
    free(ivars);
  }
}

// Retry logging with increasing delays
static void scheduleRetry(id datasource) {
  if (retryCount >= 3) return;
  retryCount++;
  dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, (int64_t)((retryCount == 1 ? 3.0 : retryCount == 2 ? 10.0 : 20.0) * NSEC_PER_SEC));
  dispatch_after(delay, dispatch_get_main_queue(), ^{
    if (datasource && !feedDumped) {
      const char *home = getenv("HOME");
      if (home) {
        char path[512];
        snprintf(path, sizeof(path), "%s/Documents/glow_feed2.txt", home);
        FILE *f = fopen(path, "a");
        if (f) {
          fprintf(f, "\n=== Retry %d ===\n", retryCount);
          fclose(f);
        }
      }
      introspectDatasource(datasource);
    }
  });
}

// Enumerate datasource and call methods
static void introspectDatasource(id datasource) {
  if (!datasource) return;

  const char *home = getenv("HOME");
  if (!home) return;

  char path[512];
  snprintf(path, sizeof(path), "%s/Documents/glow_feed.txt", home);

  FILE *f = fopen(path, "w");
  if (!f) return;

  fprintf(f, "=== FBComponentCollectionViewDataSource Introspection ===\n");
  fprintf(f, "class: %s\n", NSStringFromClass([datasource class]).UTF8String);

  // Class hierarchy
  Class cls = object_getClass(datasource);
  fprintf(f, "hierarchy:\n");
  while (cls) {
    fprintf(f, "  %s\n", class_getName(cls));
    cls = class_getSuperclass(cls);
  }

  // All methods
  fprintf(f, "\n--- All Methods ---\n");
  cls = object_getClass(datasource);
  while (cls && cls != objc_getClass("NSObject")) {
    fprintf(f, "\n%s:\n", class_getName(cls));
    logClassMethods(cls, f);
    cls = class_getSuperclass(cls);
  }

  // Try common datasource accessor methods with index paths
  fprintf(f, "\n--- Method Results (section 2, row 0) ---\n");
  NSIndexPath *ip = [NSIndexPath indexPathForRow:0 inSection:2];

  const char *methodNames[] = {
    "objectAtIndexPath:",
    "itemAtIndexPath:",
    "modelAtIndexPath:",
    "dataAtIndexPath:",
    "objectForCellAtIndexPath:",
    "componentAtIndexPath:",
    "cellModelAtIndexPath:",
    "feedUnitAtIndexPath:",
    "storyAtIndexPath:",
    "contentAtIndexPath:",
    "objectAtIndex:",
    "itemAtIndex:",
    "modelForIndexPath:",
    "objectForItemAtIndexPath:",
    "componentForItemAtIndexPath:",
    "modelForObjectAtIndexPath:",
    "feedStoryAtIndexPath:",
    "unitAtIndexPath:",
    "adAtIndexPath:",
    "sponsoredAtIndexPath:",
    "isSponsoredAtIndexPath:",
    "sponsoredStateAtIndexPath:",
    "objectAtIndexPath:inCollectionView:",
    "modelForCellAtIndexPath:",
    "dataForCellAtIndexPath:",
    "componentForCellAtIndexPath:",
    "objectForItemAt:",
    "modelForItemAt:",
    "feedObjectAtIndexPath:",
    "storyObjectAtIndexPath:",
  };

  for (int i = 0; i < (int)(sizeof(methodNames)/sizeof(methodNames[0])); i++) {
    SEL sel = NSSelectorFromString([NSString stringWithUTF8String:methodNames[i]]);
    if ([datasource respondsToSelector:sel]) {
      tryDatasourceMethod(datasource, sel, ip, f);
    }
  }

  // Also try section 0, row 0
  fprintf(f, "\n--- Method Results (section 0, row 0) ---\n");
  NSIndexPath *ip0 = [NSIndexPath indexPathForRow:0 inSection:0];
  for (int i = 0; i < (int)(sizeof(methodNames)/sizeof(methodNames[0])); i++) {
    SEL sel = NSSelectorFromString([NSString stringWithUTF8String:methodNames[i]]);
    if ([datasource respondsToSelector:sel]) {
      tryDatasourceMethod(datasource, sel, ip0, f);
    }
  }

  // Also try to access _dataSource ivar chain (depth-first)
  fprintf(f, "\n--- Ivar Chain ---\n");
  id obj = datasource;
  const char *ivarNames[] = {
    "_dataSource", "_transactionalComponentDataSource", "_state",
    "_sections", "_configuration", "_sectionedDataSourceReaderWriter",
    "_cellConfigProvider", "_feedToolbox", "_readTransform",
    "_dataSourceState", "_attachController", "_constraintProvider"
  };
  for (int i = 0; i < (int)(sizeof(ivarNames)/sizeof(ivarNames[0])); i++) {
    Ivar ivar = class_getInstanceVariable(object_getClass(obj), ivarNames[i]);
    if (ivar) {
      id val = nil;
      @try { val = object_getIvar(obj, ivar); } @catch (...) {}
      if (val && [val isKindOfClass:[NSObject class]]) {
        fprintf(f, "  %s -> %s (%p)\n", ivarNames[i], NSStringFromClass([val class]).UTF8String, (__bridge void *)val);

        NSString *valClsName = NSStringFromClass([val class]);

        // CKDataSourceState → dump _sections
        if ([valClsName containsString:@"CKDataSourceState"]) {
          Ivar sectionsIvar = class_getInstanceVariable(object_getClass(val), "_sections");
          if (sectionsIvar) {
            id sections = nil;
            @try { sections = object_getIvar(val, sectionsIvar); } @catch (...) {}
            if (sections && [sections isKindOfClass:[NSArray class]]) {
              NSArray *sectionsArray = (NSArray *)sections;
              fprintf(f, "    _sections count: %lu\n", (unsigned long)sectionsArray.count);
              for (NSUInteger s = 0; s < sectionsArray.count && s < 5; s++) {
                id section = sectionsArray[s];
                fprintf(f, "    section[%lu]: %s\n", (unsigned long)s, NSStringFromClass([section class]).UTF8String);
                dumpSectionItems(section, f, 1);
              }
              if (sectionsArray.count > 0) feedDumped = YES;
            }
          }
        }

        // CKComponentAttachController → dump scope map
        if ([valClsName containsString:@"CKComponentAttachController"]) {
          Ivar mapIvar = class_getInstanceVariable(object_getClass(val), "_scopeIdentifierToAttachedViewMap");
          if (mapIvar) {
            id map = nil;
            @try { map = object_getIvar(val, mapIvar); } @catch (...) {}
            if (map && [map isKindOfClass:[NSDictionary class]]) {
              NSDictionary *dict = (NSDictionary *)map;
              fprintf(f, "    _scopeIdentifierToAttachedViewMap count: %lu\n", (unsigned long)dict.count);
              int scopeCount = 0;
              for (id key in dict) {
                if (scopeCount++ >= 10) break;
                id view = dict[key];
                NSString *keyDesc = [key respondsToSelector:@selector(description)] ? [key performSelector:@selector(description)] : @"?";
                fprintf(f, "      scope[%d] key=%s view=%s\n",
                  scopeCount-1, keyDesc.UTF8String,
                  NSStringFromClass([view class]).UTF8String);
                // Check key for sponsored-related strings
                if ([keyDesc containsString:@"Sponsored"] || [keyDesc containsString:@"sponsored"] ||
                    [keyDesc containsString:@"AdUnit"] || [keyDesc containsString:@"Promoted"]) {
                  fprintf(f, "        *** SPONSORED SCOPE: %s\n", keyDesc.UTF8String);
                }
              }
            }
          }
          Ivar layoutIvar = class_getInstanceVariable(object_getClass(val), "_scopeIdentifierToLayoutProvider");
          if (layoutIvar) {
            id layoutMap = nil;
            @try { layoutMap = object_getIvar(val, layoutIvar); } @catch (...) {}
            if (layoutMap) {
              fprintf(f, "    _scopeIdentifierToLayoutProvider: %s\n", NSStringFromClass([layoutMap class]).UTF8String);
              if ([layoutMap isKindOfClass:[NSDictionary class]]) {
                fprintf(f, "      count: %lu\n", (unsigned long)((NSDictionary *)layoutMap).count);
              }
            }
          }
        }

        // FBSectionedDataSourceTransformer → try to log readTransform block info
        if ([valClsName containsString:@"FBSectionedDataSourceTransformer"]) {
          Ivar transIvar = class_getInstanceVariable(object_getClass(val), "_readTransform");
          if (transIvar) {
            id block = nil;
            @try { block = object_getIvar(val, transIvar); } @catch (...) {}
            if (block) {
              fprintf(f, "    _readTransform: %s\n", NSStringFromClass([block class]).UTF8String);
            }
          }
          // Also try _transactionalComponentDataSource from transformer
          Ivar tcdsIvar = class_getInstanceVariable(object_getClass(val), "_transactionalComponentDataSource");
          if (tcdsIvar) {
            id tcds = nil;
            @try { tcds = object_getIvar(val, tcdsIvar); } @catch (...) {}
            if (tcds) {
              fprintf(f, "    _transactionalComponentDataSource -> %s\n", NSStringFromClass([tcds class]).UTF8String);
              // Try to get CKDataSource from it
              Ivar dsIvar = class_getInstanceVariable(object_getClass(tcds), "_dataSource");
              if (dsIvar) {
                id ckds = nil;
                @try { ckds = object_getIvar(tcds, dsIvar); } @catch (...) {}
                if (ckds) {
                  fprintf(f, "      _dataSource -> %s\n", NSStringFromClass([ckds class]).UTF8String);
                  Ivar stateIvar = class_getInstanceVariable(object_getClass(ckds), "_state");
                  if (stateIvar) {
                    id state = nil;
                    @try { state = object_getIvar(ckds, stateIvar); } @catch (...) {}
                    if (state) {
                      fprintf(f, "      _state -> %s\n", NSStringFromClass([state class]).UTF8String);
                      dumpSectionsFromState(state, f);
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // Schedule retry if feed not yet loaded
  if (!feedDumped) {
    scheduleRetry(datasource);
  }

  fclose(f);
}



// Button tap handler
static void glowButtonTapped(id self, SEL _cmd, id sender) {
  // Re-introspect datasource on tap
  if (glowDatasourceRef) {
    retryCount = 0;
    feedDumped = NO;
    introspectDatasource(glowDatasourceRef);
  }

  const char *home = getenv("HOME");
  if (!home) return;

  char path[512];
  snprintf(path, sizeof(path), "%s/Documents/glow_tap.txt", home);

  FILE *f = fopen(path, "a");
  if (f) {
    fprintf(f, "BUTTON_TAPPED: re-introspect triggered\n");
    fclose(f);
  }
}

static void hooked_viewDidAppear(id self, SEL _cmd, BOOL animated) {
  if (orig_viewDidAppear) {
    ((void(*)(id,SEL,BOOL))orig_viewDidAppear)(self, _cmd, animated);
  }

  const char *className = class_getName(object_getClass(self));
  if (className && strstr(className, "FBNewsFeedViewController")) {
    UIViewController *vc = (UIViewController *)self;

    for (UIView *sub in vc.view.subviews) {
      NSString *subClassName = NSStringFromClass([sub class]);
      if ([subClassName containsString:@"FBNewsFeedCollectionView"] && [sub isKindOfClass:[UICollectionView class]]) {
        UICollectionView *collectionView = (UICollectionView *)sub;

        id <UICollectionViewDataSource> dataSource = collectionView.dataSource;
        if (dataSource && !methodEnumDone) {
          methodEnumDone = YES;
          glowDatasourceRef = dataSource;

          // Delay introspection to let feed load (10s initial, then retry)
          dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            introspectDatasource(glowDatasourceRef);
          });

          const char *home = getenv("HOME");
          if (home) {
            char path[512];
            snprintf(path, sizeof(path), "%s/Documents/glow_hook.txt", home);
            FILE *f = fopen(path, "a");
            if (f) {
              fprintf(f, "HOOK: datasource=%s (will introspect in 3s)\n", NSStringFromClass([dataSource class]).UTF8String);
              fclose(f);
            }
          }
        }
        break;
      }
    }
  }

  // Attach button once
  if (glowButtonAttached) return;

  UIViewController *vc = (UIViewController *)self;
  UIView *view = vc.view;
  if (!view) return;
  if (!vc.isViewLoaded || !view.window) return;

  UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
  button.frame = CGRectMake(0, 0, 60, 60);
  button.tag = kGlowButtonTag;
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

  fprintf(f, "Glow Stage P: Datasource method enumeration + delayed introspection\n\n");

  Class vcClass = objc_getClass("UIViewController");
  SEL vdaSel = @selector(viewDidAppear:);
  Method vdaM = class_getInstanceMethod(vcClass, vdaSel);
  if (vdaM) {
    orig_viewDidAppear = method_getImplementation(vdaM);
    method_setImplementation(vdaM, (IMP)hooked_viewDidAppear);
    fprintf(f, "HOOK: UIViewController.viewDidAppear:\n");
  }

  fclose(f);
}
