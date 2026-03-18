# Developer mode in Windows 
start ms-settings:developers

# Android Emulator
adb shell settings put global package_verifier_enable 0
adb shell settings put global verifier_verify_adb_installs 0
Install via Android Studio by adding new device
emulator -list-avds
emulator -avd <device_name>
emulator -avd Medium_Phone_API_36.1 -no-snapshot
emulator -avd Medium_Phone_API_36.1
emulator -avd Pixel_7

adb kill-server; adb start-server
flutter run -d emulator-5554

# Add Android SDK to PATH

# Option 1: Add to PowerShell profile (persists in all new terminals, run once)
Add-Content $PROFILE "`n`$env:Path += `";`$env:LOCALAPPDATA\Android\Sdk\emulator;`$env:LOCALAPPDATA\Android\Sdk\platform-tools`""

# Option 2: Add to user environment permanently (requires VS Code restart to take effect)
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";$env:LOCALAPPDATA\Android\Sdk\emulator;$env:LOCALAPPDATA\Android\Sdk\platform-tools", [EnvironmentVariableTarget]::User)

# Option 3: Add to current session only
$env:Path += ";$env:LOCALAPPDATA\Android\Sdk\emulator;$env:LOCALAPPDATA\Android\Sdk\platform-tools"

# iOS Simulator (macOS)

open /Applications/Xcode.app/Contents/Developer/Applications/Simulator.app

# Flutter

flutter run # Run on selected device
flutter run -d chrome # Run in browser
flutter run -d windows # Run on Windows desktop



