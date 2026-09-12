#ifndef AppVersion
#define AppVersion "0.2.0"
#endif
#ifndef AppName
#define AppName "Snapliq"
#endif
[Setup]
AppId=Snapliq.Development
AppName={#AppName}
AppVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\Snapliq Development
DefaultGroupName={#AppName}
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\outputs\windows
OutputBaseFilename=Snapliq-{#AppVersion}-windows-x64-development-setup
SetupIconFile=..\..\assets\generated\Snapliq-dark.ico
UninstallDisplayIcon={app}\Snapliq.exe
Compression=lzma2
SolidCompression=yes
CloseApplications=yes
[Files]
Source: "..\..\outputs\windows\Snapliq.exe"; DestDir: "{app}"; Flags: ignoreversion
[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\Snapliq.exe"
[Run]
Filename: "{app}\Snapliq.exe"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
