include $(THEOS)/makefiles/common.mk

# Glow for Facebook - Modular Build System (v8.2.68+)
# 
# Build all modules:
#   - Core/*.xm      - Hooks (Logos)
#   - Managers/*.m   - Business logic
#   - UI/*.m         - UI components
#   - Utils/*.m      - Utilities
#   - Tweak.x        - Entry point

TWEAK_NAME = GlowV3
GlowV3_FILES = Tweak.x \
    Core/AdBlockHooks.xm \
    Core/StorySeenHooks.xm \
    Core/StoryDownloadHooks.xm \
    Core/NewsfeedVideoHooks.xm \
    Core/VideoItemHooks.xm \
    Core/PlaybackStateHooks.xm \
    Core/ReelsDownloadHooks.xm \
    Core/LongPressHooks.xm \
    Core/ExplorerHooks.xm \
    Core/RuntimeEnumHooks.xm \
    Managers/GlowLogManager.m \
    Managers/GlowSettingsManager.m \
    Managers/GlowCacheManager.m \
    Managers/GlowStoryHandler.m \
    Managers/GlowVideoHandler.m \
    Managers/GlowReelHandler.m \
    UI/GlowSettingsViewController.m \
    Utils/GlowViewUtils.m
GlowV3_FRAMEWORKS = UIKit Photos
GlowV3_PRIVATE_FRAMEWORKS = Photos
GlowV3_CFLAGS = -fobjc-arc -Wno-error -I. -ICore -IManagers -IUI -IUtils
GlowV3_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS)/makefiles/tweak.mk
