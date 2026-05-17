ARCHS = arm64
TARGET = iphone:latest:14.0
INSTALL_TARGET_PROCESSES = Facebook

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Glow
Glow_FILES = Tweak.x
Glow_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -I$(THEOS)/include
Glow_FRAMEWORKS = UIKit Foundation AVFoundation Photos CoreGraphics CoreServices Security SystemConfiguration
Glow_LDFLAGS = -L$(THEOS)/lib -lsubstrate -lobjc

include $(THEOS_MAKE_PATH)/tweak.mk
