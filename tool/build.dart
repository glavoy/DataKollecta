/// One build entry point for every target, product, and flavor.
///
/// Replaces build_apk.ps1, build_windows.ps1 and tool/build_macos_dmg.sh so
/// the same command works on macOS and Windows.
///
///     dart run tool/build.dart apk                            # GiSTX Uganda       -> gistx.apk
///     dart run tool/build.dart apk --flavor bf                # GiSTX Burkina Faso -> gistx-bf.apk
///     dart run tool/build.dart apk --product datakollecta     # DataKollecta       -> datakollecta.apk
///     dart run tool/build.dart windows
///     dart run tool/build.dart macos                          # builds and packages a DMG
///
/// Options:
///     --flavor <name>    country flavor: uganda (default) or bf.
///                        Rejected for a product that doesn't vary by country.
///     --product <name>   gistx (default) or datakollecta.
///     --bump             bump the build number before building.
///
/// This never touches the release version (`1.3.0`) — that is a semver
/// decision only a person can make, so it is hand-edited in pubspec.yaml when
/// a release is cut.
///
/// The build number (`+9`) is different: it identifies one specific binary and
/// must increase for every artifact handed to anyone, so `--bump` is offered
/// for the common case of cutting a test build:
///
///     dart run tool/build.dart apk --product datakollecta --bump
///
/// It stays opt-in rather than automatic because a release is built once per
/// product and flavor, and all of those artifacts must share a single build
/// number — bumping unconditionally would make `apk --flavor bf` and `apk` two
/// different builds of the same release.
///
/// The flavor is passed through as --dart-define, never as a Gradle product
/// flavor: product flavors conventionally add an applicationIdSuffix, which
/// would make the second build a separate app that cannot update the first,
/// orphaning the database already on the device. The product axis, which
/// DOES need a different applicationId (GiSTX and DataKollecta are meant to
/// be two separate apps), is driven instead by generated per-product config
/// files under tool/product/ -- one mechanism that works the same way on
/// every platform, since Windows has no Gradle-flavor equivalent at all.
/// See CLAUDE.md's "two axes" section.
library;

import 'dart:io';

/// Country flavors. `define` is the value of AppConfig.country.
const _flavors = <String, ({String define, String suffix})>{
  'uganda': (define: 'Uganda', suffix: ''),
  'bf': (define: 'Burkina Faso', suffix: '-bf'),
};

/// Products. `supportsCountryFlavor` gates whether --flavor is accepted --
/// only GiSTX (FTP/SFTP) varies by country language and server;
/// DataKollecta (Supabase) never does. `supportedTargets` narrows while the
/// build mechanism is rolled out platform by platform; it should equal
/// every entry in `_targets` once a product is fully wired up everywhere.
const _products = <String,
    ({
      String displayName,
      String binaryName,
      bool supportsCountryFlavor,
      Set<String> supportedTargets,
    })>{
  'gistx': (
    displayName: 'GiSTX',
    binaryName: 'gistx',
    supportsCountryFlavor: true,
    supportedTargets: {'apk', 'windows', 'macos'},
  ),
  'datakollecta': (
    displayName: 'DataKollecta',
    binaryName: 'datakollecta',
    supportsCountryFlavor: false,
    supportedTargets: {'apk', 'windows', 'macos'},
  ),
};

const _targets = {'apk', 'windows', 'macos'};

/// Thrown by [_fail] instead of calling `exit()` directly. `exit()`
/// terminates the process immediately without running pending `finally`
/// blocks, which would leave android/product.properties stuck in whatever
/// product was mid-build if a failure happened between _applyProductConfigs
/// and _restoreDefaultProductConfigs -- exactly the un-self-healing state
/// this whole mechanism exists to avoid. A normal thrown exception lets
/// Dart run finally blocks during unwinding; main() converts it to a
/// process exit only once nothing is left pending.
class _BuildFailure implements Exception {
  final String message;
  _BuildFailure(this.message);
}

Future<void> main(List<String> args) async {
  try {
    await _build(args);
  } on _BuildFailure catch (e) {
    stderr.writeln('Error: ${e.message}');
    exit(1);
  }
}

Future<void> _build(List<String> args) async {
  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    _usage();
    if (args.isEmpty) exit(1);
    return;
  }

  final target = args.first;
  if (!_targets.contains(target)) {
    _fail('Unknown target "$target". Expected one of: ${_targets.join(', ')}.');
  }

  var flavorName = 'uganda';
  var productId = 'gistx';
  var flavorExplicitlyPassed = false;
  var bumpBuild = false;
  for (var i = 1; i < args.length; i++) {
    switch (args[i]) {
      case '--flavor':
        if (i + 1 >= args.length) _fail('--flavor needs a value.');
        flavorName = args[++i].toLowerCase();
        flavorExplicitlyPassed = true;
      case '--product':
        if (i + 1 >= args.length) _fail('--product needs a value.');
        productId = args[++i].toLowerCase();
      case '--bump':
        bumpBuild = true;
      default:
        _fail('Unknown option "${args[i]}".');
    }
  }

  final product = _products[productId];
  if (product == null) {
    _fail('Unknown product "$productId". '
        'Expected one of: ${_products.keys.join(', ')}.');
  }

  if (flavorExplicitlyPassed && !product.supportsCountryFlavor) {
    _fail('--flavor is not supported for product "$productId" '
        '(it does not vary by country).');
  }

  if (!product.supportedTargets.contains(target)) {
    _fail('Product "$productId" does not build for target "$target" yet.');
  }

  final flavor = _flavors[flavorName];
  if (flavor == null) {
    _fail('Unknown flavor "$flavorName". '
        'Expected one of: ${_flavors.keys.join(', ')}.');
  }

  if (target == 'macos' && !Platform.isMacOS) {
    _fail('Building for macOS requires macOS and Xcode.');
  }

  if (target == 'windows' && !Platform.isWindows) {
    _fail('Building for Windows requires a Windows host. The installer is '
        'packaged there too, by compiling installer.iss with Inno Setup after '
        'this script has run.');
  }

  if (bumpBuild) {
    _step('Bumping build number');
    await _run(Platform.resolvedExecutable, ['run', 'tool/update_version.dart']);
  }

  final version = _readVersion();

  final defines = <String>[
    '--dart-define=APP_PRODUCT=$productId',
    if (product.supportsCountryFlavor)
      '--dart-define=GISTX_COUNTRY=${flavor.define}',
  ];

  final flavorSuffix =
      product.supportsCountryFlavor && flavor.define != 'Uganda'
          ? ' (${flavor.define})'
          : '';
  _step('Building $target for ${product.displayName}$flavorSuffix (v$version)');

  _applyProductConfigs(productId);
  try {
    await _run('flutter', ['build', target, ...defines]);

    switch (target) {
      case 'apk':
        await _copyApk(product.binaryName, flavor.suffix, version);
      case 'windows':
        _writeInstallerConfig(productId, version);
        _report('build/windows/runner/Release/${product.binaryName}.exe');
      case 'macos':
        await _packageDmg(product.displayName, product.binaryName, version, flavor.suffix);
    }
  } finally {
    _restoreDefaultProductConfigs();
  }
}

/// Materializes tool/product/**/<productId>.* into the native project files
/// each platform reads at build time.
void _applyProductConfigs(String productId) {
  _copyProductFile('tool/product/android/$productId.properties',
      'android/product.properties');
  _copyProductFile(
      'tool/product/windows/$productId.cmake', 'windows/product.cmake');
  _copyProductFile('tool/product/windows/$productId.h',
      'windows/runner/product_strings.h');
  // The Windows executable's own icon is compiled in from a fixed path by
  // Runner.rc, so it has to be swapped per product like any other build input.
  // Its source is assets/branding rather than tool/product: it is brand
  // artwork, it already lives there, and installer.iss reads the same file for
  // SetupIconFile -- so each product has exactly one icon serving both its
  // executable and its installer.
  _copyProductFile('assets/branding/$productId.ico',
      'windows/runner/resources/app_icon.ico');
  _copyProductFile('tool/product/macos/$productId.xcconfig',
      'macos/Runner/Configs/AppInfo.xcconfig');
}

/// Restores every generated file to its committed, GiSTX-default content --
/// called from a `finally`, so a crashed build (or simply not running this
/// script) always leaves the tree buildable and `git status` clean.
void _restoreDefaultProductConfigs() => _applyProductConfigs('gistx');

void _copyProductFile(String from, String to) {
  final source = File(from);
  if (!source.existsSync()) {
    _fail('Missing product config template: $from');
  }
  source.copySync(to);
}

Future<void> _copyApk(String binaryName, String suffix, String version) async {
  final source = File('build/app/outputs/flutter-apk/app-release.apk');
  if (!source.existsSync()) {
    _fail('Expected APK not found at ${source.path}.');
  }
  final destination = 'build/app/outputs/flutter-apk/'
      '$binaryName$suffix-${_versionForFilename(version)}.apk';
  await source.copy(destination);
  _report(destination);
}

/// Writes which product was built, and at what version, into an Inno Setup
/// include so `installer.iss` packages what was actually just compiled.
///
/// Deliberately NOT one of the `_applyProductConfigs` files: those are restored
/// to their GiSTX defaults in a `finally` because they feed the compiler and
/// must not be left dirty. The installer runs *after* this script exits, so a
/// value reverted on the way out would silently package a DataKollecta build as
/// GiSTX. This file is generated and left in place instead.
///
/// It also carries the version, which `installer.iss` used to hard-code: it sat
/// at 1.0.3+2 while the app shipped 1.2.0+8, so every installer built in
/// between was mislabelled in Add/Remove Programs and in its own filename. A
/// second copy of a version number kept in sync by hand will always drift.
void _writeInstallerConfig(String productId, String version) {
  final file = File('windows/installer_config.iss');
  file.writeAsStringSync('''
; Generated by tool/build.dart -- do not edit.
; Rewritten on every Windows build; describes the build that just ran.
#define MyProduct "$productId"
#define MyAppVersion "$version"
#define MyAppVersionFile "${_versionForFilename(version)}"
''');
  _report(file.path);
}

/// Renders a version for use in a filename: `1.3.0+9` -> `1.3.0-build9`.
///
/// The build number is kept, so successive test builds of one unreleased
/// version are distinguishable as files rather than overwriting each other.
/// A literal `+` is avoided because it decodes to a space if the file is ever
/// served over HTTP.
String _versionForFilename(String version) {
  final parts = version.split('+');
  if (parts.length < 2) return parts.first;
  return '${parts.first}-build${parts[1]}';
}

/// Stages the .app beside an /Applications symlink and wraps it in a DMG.
Future<void> _packageDmg(String displayName, String binaryName, String version,
    String suffix) async {
  final appPath = 'build/macos/Build/Products/Release/$binaryName.app';
  if (!Directory(appPath).existsSync()) {
    _fail('Expected app bundle not found at $appPath.');
  }

  // Build metadata after "+" is useful internally but is left out of the
  // user-facing installer filename.
  final versionName = _versionForFilename(version);
  final outputDir = Directory('installer_output')..createSync(recursive: true);
  final dmgPath = '${outputDir.path}/$displayName$suffix-$versionName.dmg';

  final staging = Directory.systemTemp.createTempSync('$binaryName-dmg');
  try {
    await _run('ditto', [appPath, '${staging.path}/$displayName.app']);
    await _run('ln', ['-s', '/Applications', '${staging.path}/Applications']);

    final signing = await Process.run(
        'codesign', ['-dv', '--verbose=2', appPath]);
    final signed = '${signing.stdout}${signing.stderr}'
        .contains('Authority=Developer ID Application');
    if (!signed) {
      stdout.writeln('Note: not Developer ID signed or notarized. Recipients '
          'may need to Control-click the app and choose Open on first launch.');
    }

    _step('Creating disk image');
    await _run('hdiutil', [
      'create',
      '-volname', '$displayName $versionName',
      '-srcfolder', staging.path,
      '-format', 'UDZO',
      '-ov',
      dmgPath,
    ]);
    await _run('hdiutil', ['verify', dmgPath]);
    _report(dmgPath);
  } finally {
    staging.deleteSync(recursive: true);
  }
}

String _readVersion() {
  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) _fail('pubspec.yaml not found.');
  for (final line in pubspec.readAsLinesSync()) {
    if (line.trimLeft().startsWith('version:')) {
      return line.split(':').last.trim();
    }
  }
  _fail('No version found in pubspec.yaml.');
}

Future<void> _run(String executable, List<String> arguments) async {
  final process = await Process.start(executable, arguments,
      mode: ProcessStartMode.inheritStdio, runInShell: Platform.isWindows);
  final code = await process.exitCode;
  if (code != 0) {
    _fail('$executable ${arguments.join(' ')} failed with exit code $code.');
  }
}

void _step(String message) => stdout.writeln('\n==> $message');
void _report(String path) => stdout.writeln('\nCreated: $path');

Never _fail(String message) => throw _BuildFailure(message);

void _usage() {
  stdout.writeln('''
Usage: dart run tool/build.dart <target> [options]

Targets:
  apk        Android release APK
  windows    Windows release executable
  macos      macOS release app, packaged as a DMG

Options:
  --flavor <name>     uganda (default) or bf. Not supported for every product.
  --product <name>    gistx (default) or datakollecta.
  --bump              bump the build number before building.

The release version (1.3.0) is never changed by this script -- hand-edit
pubspec.yaml when cutting a release. The build number (+9) identifies one
binary and should increase for every artifact you hand to anyone:

  dart run tool/build.dart apk --product datakollecta --bump

Omit --bump when building a release, so every product and flavor of that
release carries the same build number.
''');
}
