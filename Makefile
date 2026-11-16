ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME ?= roothide
FINALPACKAGE = 1
DEBUG = 0
include $(THEOS)/makefiles/common.mk

AD_INCLUDES = $(addprefix -I,$(shell find AppData/Classes AppData/Vendors AppDataPrefs/Classes -type d)) -IAppData -IAppDataPrefs
AD_FLAGS = -fobjc-arc $(AD_INCLUDES) -include $(THEOS_PROJECT_DIR)/BuildPrefix.pch -Wno-error

TWEAK_NAME = AppData
AppData_FILES = AppData/AppData.xm $(shell find AppData/Classes AppData/Vendors -name '*.m')
AppData_CFLAGS = $(AD_FLAGS)
AppData_CCFLAGS = -std=c++14
AppData_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics CoreLocation
AppData_PRIVATE_FRAMEWORKS = CoreServices
include $(THEOS_MAKE_PATH)/tweak.mk

BUNDLE_NAME = AppDataPrefs
AppDataPrefs_FILES = $(shell find AppDataPrefs -name '*.m') AppData/Classes/Helpers/ADSettings.m
AppDataPrefs_CFLAGS = $(AD_FLAGS)
AppDataPrefs_FRAMEWORKS = UIKit Foundation
AppDataPrefs_PRIVATE_FRAMEWORKS = Preferences
AppDataPrefs_INSTALL_PATH = /Library/PreferenceBundles
AppDataPrefs_RESOURCE_DIRS = AppDataPrefs/Resources
include $(THEOS_MAKE_PATH)/bundle.mk
