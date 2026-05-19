ARCHS = arm64
TARGET = iphone:latest:14.0
INSTALL_TARGET_PROCESSES = Facebook

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Glow
Glow_FILES = Tweak.x
Glow_CFLAGS = -Wno-deprecated-declarations -fobjc-arc -Wno-arc-performSelector-leaks -Wno-error=unused-const-variable -Wno-error=frame-address
Glow_LDFLAGS = -L$(THEOS)/lib

include $(THEOS_MAKE_PATH)/tweak.mk
