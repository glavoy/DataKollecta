$ErrorActionPreference = "Stop"

Write-Host "Updating version..."
dart run tool/update_version.dart
if ($LASTEXITCODE -ne 0) {
    Write-Error "Version update failed."
}

Write-Host "Building Windows Release..."
flutter build windows

if ($LASTEXITCODE -eq 0) {
    Write-Host "Build successful!"
    $buildDir = "build\windows\runner\Release"
    if (Test-Path "$buildDir\gistx.exe") {
        Write-Host "Executable located at: $buildDir\gistx.exe"
    }
}
else {
    Write-Error "Build failed."
}
