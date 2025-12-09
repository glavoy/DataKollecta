import 'dart:io';

void main() {
  final file = File('pubspec.yaml');
  if (!file.existsSync()) {
    print('Error: pubspec.yaml not found.');
    exit(1);
  }

  final lines = file.readAsLinesSync();
  final newLines = <String>[];
  bool versionUpdated = false;
  String? newVersion;

  for (final line in lines) {
    if (line.trim().startsWith('version:') && !versionUpdated) {
      final parts = line.split(':');
      if (parts.length > 1) {
        final versionString = parts[1].trim();
        final versionParts = versionString.split('+');
        final semVer = versionParts[0].split('.');

        if (semVer.length == 3) {
          final major = int.parse(semVer[0]);
          final minor = int.parse(semVer[1]);
          final patch = int.parse(semVer[2]);

          final newPatch = patch + 1;
          newVersion = '$major.$minor.$newPatch';

          // Keep build number if present, or maybe user wants to increment that too?
          // For now, based on plan, we just increment patch and strip build number or keep it?
          // The plan said "0.0.1 -> 0.0.2". Let's reconstruct cleanly.

          newLines.add('version: $newVersion');
          versionUpdated = true;
          print('Version updated to: $newVersion');
          continue;
        }
      }
    }
    newLines.add(line);
  }

  if (versionUpdated) {
    file.writeAsStringSync(newLines.join('\n') + '\n');
  } else {
    print('Error: Could not find version line in pubspec.yaml');
    exit(1);
  }
}
