import 'package:flutter_test/flutter_test.dart';

import '../../tool/update_version.dart';

void main() {
  group('bumpBuildNumber', () {
    test('increments the build number and leaves the release name alone', () {
      expect(bumpBuildNumber('1.3.0+9'), '1.3.0+10');
      expect(bumpBuildNumber('1.2.0+8'), '1.2.0+9');
    });

    test('never touches MAJOR.MINOR.PATCH', () {
      // The whole point of the rewrite: a release number is a human decision.
      for (final version in ['1.3.0+9', '2.0.0+41', '1.3.7+9']) {
        expect(releaseNameOf(bumpBuildNumber(version)), releaseNameOf(version));
      }
    });

    test('carries a pre-release suffix through untouched', () {
      expect(bumpBuildNumber('1.3.0-rc.1+9'), '1.3.0-rc.1+10');
      expect(bumpBuildNumber('1.0.3-bf+2'), '1.0.3-bf+3');
    });

    test('a version with no build number starts counting', () {
      expect(bumpBuildNumber('1.3.0'), '1.3.0+1');
      expect(bumpBuildNumber('1.3.0-rc.1'), '1.3.0-rc.1+1');
    });

    test('the counter crosses into double and triple digits', () {
      expect(bumpBuildNumber('1.3.0+9'), '1.3.0+10');
      expect(bumpBuildNumber('1.3.0+99'), '1.3.0+100');
    });

    test('an unparseable version is rejected rather than guessed at', () {
      expect(() => bumpBuildNumber('1.3'), throwsFormatException);
      expect(() => bumpBuildNumber('not-a-version'), throwsFormatException);
      expect(() => bumpBuildNumber('1.3.0+notanumber'), throwsFormatException);
    });
  });

  group('versionLinePattern', () {
    test('captures the version from a real pubspec line', () {
      final match = versionLinePattern.firstMatch(
          'name: datakollecta\nversion: 1.3.0+8\nenvironment:\n');
      expect(match, isNotNull);
      expect(match!.group(1), '1.3.0+8');
    });

    test('does not match an indented key that merely ends in "version"', () {
      // e.g. `  min_sdk_version: 21` nested under another key.
      expect(versionLinePattern.hasMatch('  min_sdk_version: 21\n'), isFalse);
    });
  });
}
