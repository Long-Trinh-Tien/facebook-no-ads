include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GlowV3
GlowV3_FILES = Tweak.x
GlowV3_FRAMEWORKS = UIKit
GlowV3_CFLAGS = -fobjc-arc -Wno-error
GlowV3_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS)/makefiles/tweak.mk
