#ifndef AppVersion
#error AppVersion must be supplied from brand/product.json by scripts/build-windows.ps1
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
MinVersion=10.0.19041
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
Source: "..\..\outputs\windows\README.zh-CN.txt"; DestDir: "{app}"; Flags: ignoreversion
[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\Snapliq.exe"
[Run]
Filename: "{app}\Snapliq.exe"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
