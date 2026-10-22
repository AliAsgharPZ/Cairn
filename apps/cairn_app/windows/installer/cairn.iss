; Cairn Windows installer (Inno Setup) — v1.3.
; The owner asked for a real installer instead of the portable zip:
; this script packs the Flutter Windows release folder (app exe +
; DLLs + data + cairn_tool_host.exe) into Cairn-Setup.exe with a
; Start-menu shortcut and a proper uninstaller.
; Build (CI): ISCC /DAppVersion=1.3.0 /DSourceDir=<release dir> cairn.iss

#ifndef AppVersion
  #define AppVersion "1.3.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{8F3A2B10-CAFE-4DAD-BABE-CA1200001300}
AppName=Cairn
AppVersion={#AppVersion}
AppPublisher=AliAsgharPZ
DefaultDirName={autopf}\Cairn
DefaultGroupName=Cairn
DisableProgramGroupPage=yes
OutputBaseFilename=Cairn-Setup-v{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
UninstallDisplayName=Cairn

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Cairn"; Filename: "{app}\cairn_app.exe"
Name: "{autodesktop}\Cairn"; Filename: "{app}\cairn_app.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\cairn_app.exe"; Description: "Launch Cairn"; Flags: nowait postinstall skipifsilent
