; GiSTX Inno Setup Installation Script
; This script creates a Windows installer for the GiSTX application

#define MyAppName "GiSTX"
#define MyAppVersion "0.0.6"
#define MyAppPublisher "Geoff Lavoy"
#define MyAppURL "https://www.geofflavoy.com"
#define MyAppExeName "gistx.exe"

[Setup]
; NOTE: The value of AppId uniquely identifies this application. Do not use the same AppId value in installers for other applications.
AppId={{899ec069-8c97-4a3d-9d2b-712a290b6675}}
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
OutputBaseFilename=GiSTX-Setup-{#MyAppVersion}
; Compression settings
Compression=lzma2
SolidCompression=yes
; Modern look
WizardStyle=modern
; Icon for the installer (uses your app icon)
; SetupIconFile=assets\branding\datakollecta.ico
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
