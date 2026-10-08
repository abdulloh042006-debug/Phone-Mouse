set -e
flutter create --org com.abdulloh --project-name phone_mouse --platforms=android .
rm -rf test
mkdir -p lib
cp src/main.dart lib/main.dart
D=android/app/src/main/kotlin/com/abdulloh/phone_mouse
mkdir -p "$D"
cp src/MainActivity.kt "$D/MainActivity.kt"
flutter pub add permission_handler
M=android/app/src/main/AndroidManifest.xml
sed -i '0,/<application/s//<uses-permission android:name="android.permission.BLUETOOTH"\/>\n    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"\/>\n    <uses-permission android:name="android.permission.BLUETOOTH_SCAN"\/>\n    <uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE"\/>\n    <application/' "$M"
sed -i 's/minSdk = flutter.minSdkVersion/minSdk = 28/; s/minSdkVersion flutter.minSdkVersion/minSdkVersion 28/' android/app/build.gradle*
