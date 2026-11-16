from pathlib import Path
import shutil, plistlib
root=Path(__file__).resolve().parent
package=root/'AppData/Package/Library'
layout=root/'layout/Library'
layout.mkdir(parents=True,exist_ok=True)
for name in ['Application Support','PreferenceLoader']:
 shutil.copytree(package/name,layout/name,dirs_exist_ok=True)
shutil.copyfile(package/'MobileSubstrate/DynamicLibraries/AppData.plist',root/'AppData.plist')
info={'CFBundleDevelopmentRegion':'zh_CN','CFBundleExecutable':'AppDataPrefs','CFBundleIdentifier':'com.fouadraheb.AppDataPrefs','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'AppDataPrefs','CFBundlePackageType':'BNDL','CFBundleShortVersionString':'1.0','CFBundleVersion':'1','NSPrincipalClass':'ADPreferencesController'}
(root/'AppDataPrefs/Resources/Info.plist').write_bytes(plistlib.dumps(info))
# Deliberately do not copy the upstream precompiled English preference bundle.
