ARCHS = arm64
TARGET = iphone:clang:16.5:14.0
INSTALL_TARGET_PROCESSES = Facebook

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = facebooknoads
facebooknoads_FILES = Tweak.xm
facebooknoads_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

clean::
	rm -rf .theos packages
