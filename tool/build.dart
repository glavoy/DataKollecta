/// One build entry point for every target and flavor.
///
/// Replaces build_apk.ps1, build_windows.ps1 and tool/build_macos_dmg.sh so
/// the same command works on macOS and Windows.
///
///     dart run tool/build.dart apk                  # Uganda   -> gistx.apk
///     dart run tool/build.dart apk --flavor bf      # Burkina  -> gistx-bf.apk
///     dart run tool/build.dart windows
///     dart run tool/build.dart macos                # builds and packages a DMG
///
/// Options:
///     --flavor <name>   country flavor: uganda (default) or bf
///     --no-version-bump skip the patch-version increment
///
/// The flavor is passed through as --dart-define, never as a Gradle product
/// flavor: product flavors conventionally add an applicationIdSuffix, which
/// would make the second build a separate app that cannot update the first,
/// orphaning the database already on the device.
library;

import 'dart:io';

/// Country flavors. `define` is the value of AppConfig.country.
const _flavors = <String, ({String define, String suffix})>{
  'uganda': (define: 'Uganda', suffix: ''),
  'bf': (define: 'Burkina Faso', suffix: '-bf'),
};

const _targets = {'apk', 'windows', 'macos'};

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    _usage();
    exit(args.isEmpty ? 1 : 0);
  }

  final target = args.first;
  if (!_targets.contains(target)) {
    _fail('Unknown target "$target". Expected one of: ${_targets.join(', ')}.');
  }

  var flavorName = 'uganda';
  var bumpVersion = true;
  for (var i = 1; i < args.length; i++) {
    switch (args[i]) {
      case '--flavor':
        if (i + 1 >= args.length) _fail('--flavor needs a value.');
        flavorName = args[++i].toLowerCase();
      case '--no-version-bump':
        bumpVersion = false;
      default:
        _fail('Unknown option "${args[i]}".');
    }
  }

  final flavor = _flavors[flavorName];
  if (flavor == null) {
    _fail('Unknown flavor "$flavorName". '
        'Expected one of: ${_flavors.keys.join(', ')}.');
  }

  if (target == 'macos' && !Platform.isMacOS) {
    _fail('Building for macOS requires macOS and Xcode.');
  }

  if (bumpVersion) {
    _step('Updating version');
    await _run('dart', ['run', 'tool/update_version.dart']);
  }
  final version = _readVersion();

  final defines = <String>['--dart-define=GISTX_COUNTRY=${flavor.define}'];
  _step('Building $target for ${flavor.define} (v$version)');
  await _run('flutter', ['build', target, ...defines]);

  switch (target) {
    case 'apk':
      await _copyApk(flavor.suffix);
    case 'windows':
      _report('build/windows/runner/Release/gistx.exe');
    case 'macos':
      await _packageDmg(version, flavor.suffix);
  }
}

Future<void> _copyApk(String suffix) async {
  final source = File('build/app/outputs/flutter-apk/app-release.apk');
  if (!source.existsSync()) {
    _fail('Expected APK not found at ${source.path}.');
  }
  final destination = 'build/app/outputs/flutter-apk/gistx$suffix.apk';
  await source.copy(destination);
  _report(destination);
}

/// Stages the .app beside an /Applications symlink and wraps it in a DMG.
Future<void> _packageDmg(String version, String suffix) async {
  final appPath = 'build/macos/Build/Products/Release/gistx.app';
  if (!Directory(appPath).existsSync()) {
    _fail('Expected app bundle not found at $appPath.');
  }

  // Build metadata after "+" is useful internally but is left out of the
  // user-facing installer filename.
  final versionName = version.split('+').first;
  final outputDir = Directory('installer_output')..createSync(recursive: true);
  final dmgPath = '${outputDir.path}/GiSTX$suffix-$versionName.dmg';

  final staging = Directory.systemTemp.createTempSync('gistx-dmg');
  try {
    await _run('ditto', [appPath, '${staging.path}/GiSTX.app']);
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
      '-volname', 'GiSTX $versionName',
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

Never _fail(String message) {
  stderr.writeln('Error: $message');
  exit(1);
}

void _usage() {
  stdout.writeln('''
Usage: dart run tool/build.dart <target> [options]

Targets:
  apk        Android release APK
  windows    Windows release executable
  macos      macOS release app, packaged as a DMG

Options:
  --flavor <name>     uganda (default) or bf
  --no-version-bump   do not increment the patch version
''');
}
