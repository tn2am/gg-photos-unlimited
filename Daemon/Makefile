ARCHS = arm64
include $(THEOS)/makefiles/common.mk
TOOL_NAME = gotohpd
gotohpd_FILES = main.mm GSDiscoveryService.c
gotohpd_CFLAGS = -fobjc-arc -fblocks -I../Shared
gotohpd_CCFLAGS = -std=c++17
gotohpd_FRAMEWORKS = Foundation Security Network IOKit CoreFoundation
gotohpd_LIBRARIES = resolv
gotohpd_LDFLAGS = $(THEOS_PROJECT_DIR)/.build/libgotohp.a
gotohpd_CODESIGN_FLAGS = -Sentitlements.plist
gotohpd_INSTALL_PATH = /usr/libexec
include $(THEOS_MAKE_PATH)/tool.mk
