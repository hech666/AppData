ARCHS = arm64e
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME ?= roothide
FINALPACKAGE = 1
DEBUG = 0
include $(THEOS)/makefiles/common.mk

AD_INCLUDES = $(addprefix -I,$(shell find AppData/Classes AppData/Vendors -type d)) -IAppData
AD_FLAGS = -fobjc-arc $(AD_INCLUDES) -include $(THEOS_PROJECT_DIR)/BuildPrefix.pch -Wno-error

TWEAK_NAME = AppData
AppData_FILES = AppData/AppData.xm $(shell find AppData/Classes AppData/Vendors -name '*.m')
AppData_CFLAGS = $(AD_FLAGS)
AppData_CCFLAGS = -std=c++14
AppData_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics CoreLocation PhotosUI ImageIO
AppData_LIBRARIES = z
AppData_PRIVATE_FRAMEWORKS = CoreServices
include $(THEOS_MAKE_PATH)/tweak.mk

