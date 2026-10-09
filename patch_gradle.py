import glob
f = (glob.glob('android/app/build.gradle.kts') + glob.glob('android/app/build.gradle'))[0]
s = open(f).read()
if f.endswith('.kts'):
    blk = 'signingConfigs {\n        create("release") {\n            storeFile = file("release.jks")\n            storePassword = "phonemouse"\n            keyAlias = "phonemouse"\n            keyPassword = "phonemouse"\n        }\n    }\n    buildTypes {'
    s = s.replace('buildTypes {', blk, 1).replace('signingConfigs.getByName("debug")', 'signingConfigs.getByName("release")')
else:
    blk = 'signingConfigs {\n        release {\n            storeFile file("release.jks")\n            storePassword "phonemouse"\n            keyAlias "phonemouse"\n            keyPassword "phonemouse"\n        }\n    }\n    buildTypes {'
    s = s.replace('buildTypes {', blk, 1).replace('signingConfigs.debug', 'signingConfigs.release')
open(f, 'w').write(s)
