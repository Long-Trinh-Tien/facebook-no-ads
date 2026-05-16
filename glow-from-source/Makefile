ARCHS = arm64
TARGET = iphone:latest:14.0
INSTALL_TARGET_PROCESSES = Facebook

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = glowfb
glowfb_FILES = Tweak.xm
glowfb_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -I$(THEOS)/include
glowfb_FRAMEWORKS = UIKit Foundation AVFoundation Photos CoreGraphics CoreServices Security SystemConfiguration
glowfb_LDFLAGS = -L$(THEOS)/lib -lsubstrate

include $(THEOS_MAKE_PATH)/tweak.mk
