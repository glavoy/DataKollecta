# GiSTX Build Instructions

This document provides step-by-step instructions for building GiSTX for different platforms.

## Prerequisites

- Flutter SDK (3.38.3 or later)
- For Windows builds: Windows 10 or later with Visual Studio
- For Android builds: Android Studio with Android SDK
- For Linux builds: Linux development environment with required libraries
- For Windows installer: Inno Setup (https://jrsoftware.org/isdl.php)

## Android APK Build

### Debug APK (for testing)
```bash
flutter build apk --debug
```
Output: `build/app/outputs/flutter-apk/app-debug.apk`

### Release APK (for distribution)
```bash
flutter build apk --release
```
Output: `build/app/outputs/flutter-apk/app-release.apk`

### Split APKs by ABI (smaller file sizes)
```bash
flutter build apk --split-per-abi --release
```
Output: Multiple APKs in `build/app/outputs/flutter-apk/`:
- `app-armeabi-v7a-release.apk` (32-bit ARM)
- `app-arm64-v8a-release.apk` (64-bit ARM)
- `app-x86_64-release.apk` (64-bit x86)

### Android App Bundle (for Google Play Store)
```bash
flutter build appbundle --release
```
Output: `build/app/outputs/bundle/release/app-release.aab`

**Note:** For release builds, you'll need to sign the APK. See Flutter's documentation on signing: https://docs.flutter.dev/deployment/android#signing-the-app

---

## Windows Executable Build

### Build Windows Release Executable
```bash
flutter build windows --release
```
Output: `build\windows\x64\runner\Release\datakollecta.exe`

**Important:** The executable requires all DLL files and the `data` folder to run. The entire `Release` folder must be distributed together.

### Contents to Distribute
When distributing the Windows executable, include all files from `build\windows\x64\runner\Release\`:
- `datakollecta.exe` - Main executable
- `flutter_windows.dll` - Flutter engine
- `flutter_secure_storage_windows_plugin.dll` - Plugin DLL
- `data\` folder - Contains all app assets and resources

You can zip this entire folder for distribution, or create an installer (see below).

---

## Windows Installer Build

### Prerequisites
1. Download and install Inno Setup from https://jrsoftware.org/isdl.php
2. Ensure you have built the Windows release executable first (see above)

### Steps to Create Installer

1. **Build the Windows executable** (if not already done):
   ```bash
   flutter build windows --release
   ```

2. **Compile the installer script**:

   **Option A: Using Inno Setup GUI**
   - Open Inno Setup Compiler
   - File → Open → Select `installer.iss`
   - Build → Compile (or press Ctrl+F9)

   **Option B: Using Command Line**
   ```bash
   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer.iss
   ```

3. **Find your installer**:
   Output: `installer_output\GiSTX-Setup-1.0.0.exe`

### Updating Version Numbers
Before building a new version:
1. Open `installer.iss`
2. Update `#define MyAppVersion "1.0.0"` to your new version number
3. The output filename will automatically update

---

## Linux Build

### Install Required Dependencies
```bash
sudo apt-get update
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev
```

### Build Linux Release
```bash
flutter build linux --release
```
Output: `build/linux/x64/release/bundle/`

### Contents to Distribute
The entire `bundle` folder contains:
- `datakollecta` - Main executable
- `lib/` - Required shared libraries
- `data/` - App assets and resources

### Creating a Linux Installer

#### Option 1: AppImage (Recommended)
AppImage creates a single executable file that runs on most Linux distributions.

1. Install `appimagetool`:
   ```bash
   wget https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
   chmod +x appimagetool-x86_64.AppImage
   ```

2. Create AppDir structure:
   ```bash
   mkdir -p GiSTX.AppDir/usr/bin
   mkdir -p GiSTX.AppDir/usr/lib
   mkdir -p GiSTX.AppDir/usr/share/applications
   mkdir -p GiSTX.AppDir/usr/share/icons/hicolor/256x256/apps
   ```

3. Copy files:
   ```bash
   cp -r build/linux/x64/release/bundle/* GiSTX.AppDir/usr/bin/
   cp assets/branding/datakollecta.png GiSTX.AppDir/usr/share/icons/hicolor/256x256/apps/datakollecta.png
   ```

4. Create desktop entry (`GiSTX.AppDir/usr/share/applications/datakollecta.desktop`):
   ```ini
   [Desktop Entry]
   Type=Application
   Name=GiSTX
   Exec=datakollecta
   Icon=datakollecta
   Categories=Utility;
   ```

5. Create AppRun script (`GiSTX.AppDir/AppRun`):
   ```bash
   #!/bin/bash
   SELF=$(readlink -f "$0")
   HERE=${SELF%/*}
   export PATH="${HERE}/usr/bin/:${HERE}/usr/sbin/:${HERE}/usr/games/:${HERE}/bin/:${HERE}/sbin/${PATH:+:$PATH}"
   export LD_LIBRARY_PATH="${HERE}/usr/lib/:${HERE}/usr/lib/i386-linux-gnu/:${HERE}/usr/lib/x86_64-linux-gnu/:${HERE}/usr/lib32/:${HERE}/usr/lib64/${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
   EXEC=$(grep -e '^Exec=.*' "${HERE}"/*.desktop | head -n 1 | cut -d "=" -f 2 | cut -d " " -f 1)
   exec "${EXEC}" "$@"
   ```

6. Make AppRun executable:
   ```bash
   chmod +x GiSTX.AppDir/AppRun
   ```

7. Build AppImage:
   ```bash
   ./appimagetool-x86_64.AppImage GiSTX.AppDir
   ```

Output: `GiSTX-x86_64.AppImage`

#### Option 2: Debian Package (.deb)
For Debian/Ubuntu-based distributions:

1. Create package structure:
   ```bash
   mkdir -p datakollecta-deb/DEBIAN
   mkdir -p datakollecta-deb/opt/datakollecta
   mkdir -p datakollecta-deb/usr/share/applications
   mkdir -p datakollecta-deb/usr/share/icons/hicolor/256x256/apps
   ```

2. Copy files:
   ```bash
   cp -r build/linux/x64/release/bundle/* datakollecta-deb/opt/datakollecta/
   cp assets/branding/datakollecta.png datakollecta-deb/usr/share/icons/hicolor/256x256/apps/
   ```

3. Create control file (`datakollecta-deb/DEBIAN/control`):
   ```
   Package: datakollecta
   Version: 1.0.0
   Section: utils
   Priority: optional
   Architecture: amd64
   Maintainer: Geoff Lavoy <your-email@example.com>
   Description: Cross-platform Questionnaire software
    GiSTX is a cross-platform questionnaire application built with Flutter.
   ```

4. Create desktop entry (`datakollecta-deb/usr/share/applications/datakollecta.desktop`):
   ```ini
   [Desktop Entry]
   Type=Application
   Name=GiSTX
   Exec=/opt/datakollecta/datakollecta
   Icon=datakollecta
   Categories=Utility;
   Terminal=false
   ```

5. Build the package:
   ```bash
   dpkg-deb --build datakollecta-deb
   ```

Output: `datakollecta-deb.deb`

#### Option 3: Simple Tarball
For manual installation:
```bash
cd build/linux/x64/release
tar -czf datakollecta-linux-x64.tar.gz bundle/
```

Users can extract and run:
```bash
tar -xzf datakollecta-linux-x64.tar.gz
cd bundle
./datakollecta
```

---

## Quick Reference

| Platform | Command | Output Location |
|----------|---------|----------------|
| Android APK | `flutter build apk --release` | `build/app/outputs/flutter-apk/app-release.apk` |
| Android Bundle | `flutter build appbundle --release` | `build/app/outputs/bundle/release/app-release.aab` |
| Windows EXE | `flutter build windows --release` | `build\windows\x64\runner\Release\datakollecta.exe` |
| Windows Installer | `ISCC.exe installer.iss` | `installer_output\GiSTX-Setup-1.0.0.exe` |
| Linux Binary | `flutter build linux --release` | `build/linux/x64/release/bundle/datakollecta` |

---

## Common Issues

### After `flutter clean`
Always rebuild before creating installers:
```bash
flutter clean
flutter pub get
flutter build windows --release  # or apk, linux, etc.
```

### Missing Dependencies
If build fails, ensure all dependencies are installed:
```bash
flutter doctor -v
```

### Signing APKs for Release
You need to create a keystore and configure signing. See:
https://docs.flutter.dev/deployment/android#signing-the-app

---

## Additional Resources

- Flutter deployment documentation: https://docs.flutter.dev/deployment
- Android deployment: https://docs.flutter.dev/deployment/android
- Windows deployment: https://docs.flutter.dev/deployment/windows
- Linux deployment: https://docs.flutter.dev/deployment/linux
- Inno Setup documentation: https://jrsoftware.org/ishelp/
