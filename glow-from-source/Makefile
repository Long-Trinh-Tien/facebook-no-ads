ARCHS = arm64
TARGET = iphone:latest:14.0
INSTALL_TARGET_PROCESSES = Facebook

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = glowfb
glowfb_FILES = Tweak.xm
glowfb_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/tweak.mk
