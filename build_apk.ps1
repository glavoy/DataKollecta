Write-Host "Updating version..."
dart run tool/update_version.dart
if ($LASTEXITCODE -ne 0) {
    Write-Error "Version update failed."
}

Write-Host "Building APK..."
flutter build apk

if ($?) {
    Write-Host "Build successful. Renaming to datakollecta.apk..."
    $source = "build\app\outputs\flutter-apk\app-release.apk"
    $dest = "build\app\outputs\flutter-apk\datakollecta.apk"
    
    if (Test-Path $source) {
        Copy-Item -Path $source -Destination $dest -Force
        Write-Host "APK created at: $dest"
    }
    else {
        Write-Host "Error: Could not find output APK at $source"
    }
}
else {
    Write-Host "Build failed."
}
