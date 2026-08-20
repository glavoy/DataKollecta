; Inno Setup installation script for both products built from this codebase.
;
; Which product it packages is NOT chosen here -- it comes from
; windows\installer_config.iss, which `dart run tool/build.dart windows
; [--product datakollecta]` rewrites on every build, along with the version.
; So the sequence is always: build, then compile this script. Packaging without
; building first cannot work anyway, since there would be no .exe to collect.
;
;   dart run tool/build.dart windows                          -> GiSTX
;   dart run tool/build.dart windows --product datakollecta    -> DataKollecta
;
#include "windows\installer_config.iss"

#define MyAppPublisher "Geoff Lavoy"
#define MyAppURL "https://www.geofflavoy.com"

#if MyProduct == "datakollecta"
  #define MyAppName "DataKollecta"
  #define MyAppExeName "datakollecta.exe"
  #define MyAppIcon "assets\branding\datakollecta.ico"
#else
  #define MyAppName "GiSTX"
  #define MyAppExeName "gistx.exe"
  #define MyAppIcon "assets\branding\gistx.ico"
#endif

[Setup]
; NOTE: The value of AppId uniquely identifies this application. Do not use the same AppId value in installers for other applications.
; GiSTX and DataKollecta are two separate applications and must never share an
; AppId -- Windows identifies an installation by it, so a shared value would
; make installing one upgrade and replace the other, exactly as a shared
; applicationId would on Android. Neither may ever be changed once shipped:
; changing an AppId orphans every existing installation's uninstall entry.
#if MyProduct == "datakollecta"
AppId={{0C203832-5C03-4935-9610-DD07C8442579}}
#else
AppId={{899ec069-8c97-4a3d-9d2b-712a290b6675}}
#endif
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
; Uncomment the following line to disable the "Select Start Menu Folder" page
;DisableProgramGroupPage=yes
; License file (uncomment and create if you have one)
;LicenseFile=LICENSE.txt
; Output directory and filename
OutputDir=installer_output
OutputBaseFilename={#MyAppName}-Setup-{#MyAppVersionFile}
; Compression settings
Compression=lzma2
SolidCompression=yes
; Modern look
WizardStyle=modern
; Icon for the installer (uses your app icon)
SetupIconFile={#MyAppIcon}
; Uninstall icon
UninstallDisplayIcon={app}\{#MyAppExeName}
; Architecture
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Privileges
PrivilegesRequired=admin
; Minimum Windows version (Windows 10)
MinVersion=10.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Include all files from the Release build
Source: "build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
