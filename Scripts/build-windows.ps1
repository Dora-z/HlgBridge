param([switch]$SkipInstall)
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot
function Run-Checked {
    param([string]$Executable, [string[]]$Arguments)
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): $Executable" }
}
if (-not (Test-Path .build/windows-venv/Scripts/python.exe)) {
    Run-Checked python @("-m", "venv", ".build/windows-venv")
}
$PythonExe = Join-Path $ProjectRoot ".build/windows-venv/Scripts/python.exe"
if (-not $SkipInstall) {
    Run-Checked $PythonExe @("-m", "pip", "install", "-r", "Windows/requirements-build.txt")
}
Run-Checked cmake @("-S", "Windows/native", "-B", ".build/windows-native", "-A", "x64")
Run-Checked cmake @("--build", ".build/windows-native", "--config", "Release", "--target", "hlgcodec", "--parallel", "4")
$CodecPath = Join-Path $ProjectRoot ".build/windows-native/Release/hlgcodec.dll"
$env:HLGBRIDGE_CODEC = $CodecPath
$env:PYTHONPATH = Join-Path $ProjectRoot "Windows"
$env:QT_QPA_PLATFORM = "offscreen"
Run-Checked $PythonExe @("-m", "unittest", "discover", "-s", "Windows/tests", "-v")
Run-Checked $PythonExe @("Windows/package_assets.py")
Run-Checked $PythonExe @("Windows/app.py", "--self-test", ".build/windows-source-smoke.json")
Run-Checked $PythonExe @("-m", "PyInstaller", "--noconfirm", "--clean", "--windowed", "--onedir",
    "--name", "HlgBridge", "--distpath", "dist/windows", "--workpath", ".build/windows-pyinstaller",
    "--specpath", ".build/windows-spec", "--icon", ".build/windows-assets/AppIcon.ico",
    "--additional-hooks-dir", "Windows/hooks", "--add-binary", "$CodecPath;native",
    "--add-data", "Assets/AppIcon.png;Assets", "--add-data", ".build/windows-assets/AppIcon.ico;Assets",
    "--add-data", ".build/windows-assets/Licenses;Licenses", "Windows/app.py")
# The packaged self-test must load the bundled DLL, not the source build override.
Remove-Item Env:HLGBRIDGE_CODEC
$Report = Join-Path $ProjectRoot ".build/windows-packaged-smoke.json"
$AppExe = Join-Path $ProjectRoot "dist/windows/HlgBridge/HlgBridge.exe"
$Process = Start-Process -FilePath $AppExe -ArgumentList @("--self-test", ('"' + $Report + '"')) -Wait -PassThru
if ($Process.ExitCode -ne 0 -or -not (Test-Path $Report)) { throw "Packaged app self-test failed." }
$Smoke = Get-Content $Report -Raw | ConvertFrom-Json
if (-not $Smoke.success) { throw "Packaged app self-test failed: $($Smoke.error)" }
Copy-Item Windows/使用说明.txt dist/windows/HlgBridge/使用说明.txt
Compress-Archive -Path dist/windows/HlgBridge -DestinationPath dist/HlgBridge-v1.2.0-Windows-x64.zip -Force
Write-Host "Built: dist/HlgBridge-v1.2.0-Windows-x64.zip"
