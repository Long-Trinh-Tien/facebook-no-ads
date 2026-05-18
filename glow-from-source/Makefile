ARCHS = arm64
TARGET = iphone:latest:14.0
INSTALL_TARGET_PROCESSES = Facebook

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Glow
Glow_FILES = Tweak.x
Glow_CFLAGS = -Wno-deprecated-declarations
Glow_FRAMEWORKS = UIKit Foundation CoreGraphics
Glow_LDFLAGS = -L$(THEOS)/lib

include $(THEOS_MAKE_PATH)/tweak.mk
