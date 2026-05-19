TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = Discord
ARCHS = arm64
THEOS_PACKAGE_SCHEME ?= rootless
FINALPACKAGE = 1
DNT_DEBUG ?= 0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DiscordNoTrack

$(TWEAK_NAME)_FILES = DiscordNoTrack.xm dummyDelegate.m
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -DDNT_DEBUG=$(DNT_DEBUG)
$(TWEAK_NAME)_LOGOS_DEFAULT_GENERATOR = internal

include $(THEOS_MAKE_PATH)/tweak.mk

after-stage::
	$(ECHO_NOTHING)find $(THEOS_STAGING_DIR) -name ".DS_Store" -delete$(ECHO_END)
	$(ECHO_NOTHING)find $(THEOS_STAGING_DIR) -name "._*" -delete$(ECHO_END)
