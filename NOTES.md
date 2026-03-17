# Developer mode in Windows 
start ms-settings:developers

# Android Emulator
Install via Android Studio by adding new device
emulator -list-avds
emulator -avd <device_name>
emulator -avd Medium_Phone_API_36.1 -no-snapshot
emulator -avd Medium_Phone_API_36.1
emulator -avd Pixel_7

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






0 - Snake (coiled in a circle)
1 - Giraffe (tall and straight)
2 - Swan (curved neck)
3 - Butterfly (two wings resemble the number)
4 - Flamingo (standing on one leg)
5 - Seahorse (curved body and snout)
6 - Elephant (trunk curved upwards)
7 - Toucan (large beak forming the top bar)
8 - Snowman/Panda (two round circles)
9 - Narwhal (round head with a long horn)
10 - Lion and Hoop (the "1" as the trainer and "0" as the hoop)
11 - Two Zebras (standing side-by-side)
12 - Whale and Duck
13 - Caterpillar and Bee
14 - Fox and Shark
15 - Penguin and Turtle
16 - Rabbit and Snail
17 - Monkey and Tiger
18 - Horse and Owl
19 - Koala and Jellyfish
20 - Swan and Egg (the "2" is the swan, "0" is the egg)


