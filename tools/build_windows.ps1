# Build Cairn for Windows on the owner's PC (alternative to the
# windows-build GitHub Actions workflow). Produces the release folder
# with Cairn.exe AND cairn_tool_host.exe side by side — the app
# spawns the Tool Host at startup and connects over a Named Pipe.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

flutter config --enable-windows-desktop | Out-Null

Push-Location "$root\apps\cairn_app"
flutter test
flutter build windows --release
Pop-Location

Push-Location "$root\packages\cairn_toolhost"
dart pub get
dart compile exe bin/cairn_tool_host.dart -o "$root\apps\cairn_app\build\windows\x64\runner\Release\cairn_tool_host.exe"
Pop-Location

Write-Host "Done: apps\cairn_app\build\windows\x64\runner\Release\"
