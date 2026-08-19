# Build Instructions

This document provides step-by-step instructions for building GiSTX and DataKollecta — the two products built from this repository — for different platforms.

## Prerequisites

- Flutter SDK (3.44 or later)
- For Windows builds: Windows 10 or later with Visual Studio
- For Android builds: Android Studio with Android SDK
- For Linux builds: Linux development environment with required libraries
- For Windows installer: Inno Setup (https://jrsoftware.org/isdl.php)

## One build script for every target

It behaves identically on macOS and Windows.

```bash
dart run tool/build.dart apk                            # GiSTX Uganda       -> gistx.apk
dart run tool/build.dart apk --flavor bf                # GiSTX Burkina Faso -> gistx-bf.apk
dart run tool/build.dart apk --product datakollecta      # DataKollecta       -> datakollecta.apk
dart run tool/build.dart windows                         # -> build/windows/runner/Release/gistx.exe
dart run tool/build.dart macos                           # -> installer_output/GiSTX-<version>.dmg
```

**The country is chosen at build time, not at runtime.** `--flavor bf` compiles
the French/SFTP variant; the default is English/FTP. Both flavours keep the same
application id and signing key, so either updates an existing installation in
place without losing the device's database.

**The product is a separate axis, chosen the same way.** `--product datakollecta`
builds DataKollecta (Supabase/HTTP sync) instead of the default GiSTX (FTP/SFTP).
Unlike the country flavors, the two products have **different** application ids
and **different** signing keys — they are meant to install side by side as
separate apps, not update each other. `--flavor` is rejected for DataKollecta,
since it doesn't vary by country. See `CLAUDE.md`'s "Product flavors" section for
how the underlying mechanism works, and the "Android APK Build" section below for
DataKollecta's signing key.

### Versioning

**The build script never changes the version.** Both flavours of a release must
carry the same version, and test builds should not consume version numbers.
Bump deliberately when cutting a release, and update `ChangeLog.md` at the same
time:

```bash
dart run tool/update_version.dart   # increments the patch version in pubspec.yaml
```

Android decides whether an APK is an update or a downgrade using the
**`versionCode`** — the number after the `+` in `pubspec.yaml`, not the version
name. A lower `versionCode` is rejected outright, and the only way to install it
is to uninstall first, which deletes the survey database on that device.

**The build number must only ever increase, whatever the version name does.**

---

## Android APK Build

Use `dart run tool/build.dart apk` (above) for anything you intend to
distribute — it applies the release signing config and names the output per
flavour.

The raw Flutter commands below are for local experiments only.

### Debug APK (for testing)
```bash
flutter build apk --debug
```
Output: `build/app/outputs/flutter-apk/app-debug.apk`

### Split APKs by ABI (smaller file sizes)
```bash
flutter build apk --split-per-abi --release
```
Output: Multiple APKs in `build/app/outputs/flutter-apk/`:
- `app-armeabi-v7a-release.apk` (32-bit ARM)
- `app-arm64-v8a-release.apk` (64-bit ARM)
- `app-x86_64-release.apk` (64-bit x86)

### Signing

Release builds are signed with the project keystore, configured through
`android/key.properties`. That file and the keystore itself are gitignored and
are **not** in this repository — the keystore, its password and the setup
instructions are kept with the keystore backup.

A release signed with a different key cannot update an installed app; the only
way to install it is to uninstall first, which deletes the device's database.
Never generate a replacement keystore, and never change `applicationId` (it is
`com.gistx.gistx` for both flavours).

**DataKollecta uses a separate keystore**, `android/key-datakollecta.properties`
(same gitignored treatment, same format as `key.properties`). It's a genuinely
different `.jks` file with its own password and alias — deliberately, since
`com.datakollecta.datakollecta` is a different app with a different install
base, so there's no reason to share signing-key blast radius with GiSTX's
production Burkina Faso deployment. A `--product datakollecta` build fails at
Gradle configuration time with a readable error if this file is missing.

---

## Windows Executable Build

```bash
dart run tool/build.dart windows
```
Output: `build\windows\runner\Release\gistx.exe`

The underlying Flutter command is `flutter build windows --release`.

**Important:** The executable requires all DLL files and the `data` folder to run. The entire `Release` folder must be distributed together.

### Contents to Distribute
When distributing the Windows executable, include all files from `build\windows\runner\Release\`:
- `gistx.exe` - Main executable
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
- `gistx` - Main executable
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
   cp assets/branding/gistx.png GiSTX.AppDir/usr/share/icons/hicolor/256x256/apps/gistx.png
   ```

4. Create desktop entry (`GiSTX.AppDir/usr/share/applications/gistx.desktop`):
   ```ini
   [Desktop Entry]
   Type=Application
   Name=GiSTX
   Exec=gistx
   Icon=gistx
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
   mkdir -p gistx-deb/DEBIAN
   mkdir -p gistx-deb/opt/gistx
   mkdir -p gistx-deb/usr/share/applications
   mkdir -p gistx-deb/usr/share/icons/hicolor/256x256/apps
   ```

2. Copy files:
   ```bash
   cp -r build/linux/x64/release/bundle/* gistx-deb/opt/gistx/
   cp assets/branding/gistx.png gistx-deb/usr/share/icons/hicolor/256x256/apps/
   ```

3. Create control file (`gistx-deb/DEBIAN/control`):
   ```
   Package: gistx
   Version: 1.0.0
   Section: utils
   Priority: optional
   Architecture: amd64
   Maintainer: Geoff Lavoy <your-email@example.com>
   Description: Cross-platform Questionnaire software
    GiSTX is a cross-platform questionnaire application built with Flutter.
   ```

4. Create desktop entry (`gistx-deb/usr/share/applications/gistx.desktop`):
   ```ini
   [Desktop Entry]
   Type=Application
   Name=GiSTX
   Exec=/opt/gistx/gistx
   Icon=gistx
   Categories=Utility;
   Terminal=false
   ```

5. Build the package:
   ```bash
   dpkg-deb --build gistx-deb
   ```

Output: `gistx-deb.deb`

#### Option 3: Simple Tarball
For manual installation:
```bash
cd build/linux/x64/release
tar -czf gistx-linux-x64.tar.gz bundle/
```

Users can extract and run:
```bash
tar -xzf gistx-linux-x64.tar.gz
cd bundle
./gistx
```

---

## Quick Reference

| Platform | Command | Output Location |
|----------|---------|----------------|
| Android APK (Uganda) | `dart run tool/build.dart apk` | `build/app/outputs/flutter-apk/gistx.apk` |
| Android APK (Burkina Faso) | `dart run tool/build.dart apk --flavor bf` | `build/app/outputs/flutter-apk/gistx-bf.apk` |
| Windows EXE | `dart run tool/build.dart windows` | `build\windows\runner\Release\gistx.exe` |
| macOS DMG | `dart run tool/build.dart macos` | `installer_output/GiSTX-<version>.dmg` |
| Windows Installer | `ISCC.exe installer.iss` | `installer_output\GiSTX-Setup-<version>.exe` |
| Linux Binary | `flutter build linux --release` | `build/linux/x64/release/bundle/gistx` |

---

## Common Issues

### After `flutter clean`
Always rebuild before creating installers:
```bash
flutter clean
flutter pub get
dart run tool/build.dart windows   # or apk, macos
```

### Missing Dependencies
If build fails, ensure all dependencies are installed:
```bash
flutter doctor -v
```

### The APK will not install over the existing app
Two causes, both covered above:

- **Signed with a different key.** The keystore must be the project one. Verify
  with `apksigner verify --print-certs <apk>`.
- **`versionCode` is the same or lower** than the installed build. Check the
  number after the `+` in `pubspec.yaml`.

Do **not** solve either by uninstalling the app on a device that holds real
data — uninstalling deletes the survey database and resets the subject-ID
counter.

### Language-dependent tests
Widget tests that assert on text must pass in both flavours:

```bash
flutter test
flutter test --dart-define=GISTX_COUNTRY="Burkina Faso"
```

---

## Additional Resources

- Flutter deployment documentation: https://docs.flutter.dev/deployment
- Android deployment: https://docs.flutter.dev/deployment/android
- Windows deployment: https://docs.flutter.dev/deployment/windows
- Linux deployment: https://docs.flutter.dev/deployment/linux
- Inno Setup documentation: https://jrsoftware.org/ishelp/
