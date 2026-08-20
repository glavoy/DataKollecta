import 'dart:io';

/// Bumps the build number in `pubspec.yaml` and nothing else.
///
/// A Flutter version is `NAME+BUILD`, and the two halves answer different
/// questions. `NAME` (`1.3.0`) is the *release* — chosen deliberately by semver
/// when a release is cut, and hand-edited, because only a person knows whether
/// a change set is a fix, a feature or a break. `BUILD` (`+9`) identifies one
/// specific binary; it must increase for every artifact handed to anyone and
/// must never repeat, which is exactly the sort of bookkeeping a script should
/// own.
///
/// So this script moves `+9` to `+10` and leaves `1.3.0` alone. Run it
/// immediately *before* each build, so the version in `pubspec.yaml` at rest
/// always names the last binary that actually exists.
///
///     dart run tool/update_version.dart
///     dart run tool/build.dart apk --product datakollecta
///
/// (`tool/build.dart --bump` does both in one step.)
void main() {
  final file = File('pubspec.yaml');
  if (!file.existsSync()) {
    stderr.writeln('Error: pubspec.yaml not found. Run this from the '
        'project root.');
    exit(1);
  }

  final contents = file.readAsStringSync();
  final match = versionLinePattern.firstMatch(contents);
  if (match == null) {
    stderr.writeln('Error: could not find a parseable "version:" line in '
        'pubspec.yaml.');
    exit(1);
  }

  final current = match.group(1)!;
  final String updated;
  try {
    updated = bumpBuildNumber(current);
  } on FormatException catch (e) {
    stderr.writeln('Error: $e');
    exit(1);
  }

  file.writeAsStringSync(
      contents.replaceFirst(versionLinePattern, 'version: $updated'));

  stdout.writeln('Build number bumped: $current -> $updated');
  stdout.writeln('Release version ${releaseNameOf(updated)} is unchanged -- '
      'edit pubspec.yaml by hand to change it.');
}

/// Matches the `version:` line and captures the version itself.
final RegExp versionLinePattern =
    RegExp(r'^version:[ \t]*(\S+)[ \t]*$', multiLine: true);

/// Splits a Flutter version into its release name and optional build number.
///
/// Accepts a pre-release suffix (`1.3.0-rc.1+9`), which semver allows on the
/// name; the suffix belongs to the release name and is carried through
/// untouched.
final RegExp _versionPattern =
    RegExp(r'^((?:\d+)\.(?:\d+)\.(?:\d+)(?:-[A-Za-z0-9.]+)?)(?:\+(\d+))?$');

/// The release-name half of [version] -- everything before the `+`.
String releaseNameOf(String version) {
  final match = _versionPattern.firstMatch(version);
  if (match == null) throw FormatException('unrecognized version "$version"');
  return match.group(1)!;
}

/// Returns [version] with its build number incremented by one, leaving the
/// release name exactly as it was.
///
/// A version carrying no build number at all gains `+1`, so a pubspec that has
/// never had one starts counting rather than failing.
String bumpBuildNumber(String version) {
  final match = _versionPattern.firstMatch(version);
  if (match == null) {
    throw FormatException(
        'unrecognized version "$version" -- expected MAJOR.MINOR.PATCH[-suffix][+BUILD]');
  }

  final name = match.group(1)!;
  final build = match.group(2);
  final next = build == null ? 1 : int.parse(build) + 1;

  return '$name+$next';
}
