# Build Instructions – Windows

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install/windows)
- Windows Developer Mode enabled: `start ms-settings:developers`
- Visual Studio 2022 with **Desktop development with C++** workload

## Run in debug mode

```powershell
flutter run -d windows
```

## Build release executable

```powershell
flutter build windows
```

Output: `build\windows\x64\runner\Release\`

The `.exe` requires the DLLs and `data\` folder next to it — distribute the entire `Release\` folder.

## Create an installer (optional)

Requires [Inno Setup](https://jrsoftware.org/isdl.php) installed.

```powershell
# 1. Build the release first
flutter build windows

# 2. Open installer.iss in Inno Setup Compiler and press F9 (or use the CLI below)
iscc installer.iss
```

Output: `installer_output\SimonsenFlashcard_Setup.exe`

This is a single self-contained installer that users can run to install the app.
