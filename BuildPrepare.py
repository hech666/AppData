from pathlib import Path
import shutil, plistlib
root=Path(__file__).resolve().parent
package=root/'AppData/Package/Library'
layout=root/'layout/Library'
layout.mkdir(parents=True,exist_ok=True)
for old in ['PreferenceLoader', 'PreferenceBundles']:
 shutil.rmtree(layout/old,ignore_errors=True)
for name in ['Application Support']:
 shutil.copytree(package/name,layout/name,dirs_exist_ok=True)
shutil.copyfile(package/'MobileSubstrate/DynamicLibraries/AppData.plist',root/'AppData.plist')
