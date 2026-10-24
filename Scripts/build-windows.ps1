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
& $PythonExe -X faulthandler Windows/app.py --self-test .build/windows-source-smoke.json
$SourceExit = $LASTEXITCODE
if (Test-Path .build/windows-source-smoke.json) { Get-Content .build/windows-source-smoke.json -Raw | Write-Host }
if (Test-Path .build/windows-source-smoke.fault.log) { Get-Content .build/windows-source-smoke.fault.log -Raw | Write-Host }
if ($SourceExit -ne 0) { throw "Source Qt smoke test failed ($SourceExit)." }
$IconPng = Join-Path $ProjectRoot "Assets/AppIcon.png"
$IconIco = Join-Path $ProjectRoot ".build/windows-assets/AppIcon.ico"
$LicenseDir = Join-Path $ProjectRoot ".build/windows-assets/Licenses"
$HooksDir = Join-Path $ProjectRoot "Windows/hooks"
$AppScript = Join-Path $ProjectRoot "Windows/app.py"
Run-Checked $PythonExe @("-m", "PyInstaller", "--noconfirm", "--clean", "--windowed", "--onedir",
    "--name", "HlgBridge", "--distpath", "dist/windows", "--workpath", ".build/windows-pyinstaller",
    "--specpath", ".build/windows-spec", "--icon", $IconIco,
    "--additional-hooks-dir", $HooksDir, "--add-binary", "$CodecPath;native",
    "--add-data", "$IconPng;Assets", "--add-data", "$IconIco;Assets",
    "--add-data", "$LicenseDir;Licenses", $AppScript)
# The packaged self-test must load the bundled DLL, not the source build override.
Remove-Item Env:HLGBRIDGE_CODEC
$Report = Join-Path $ProjectRoot ".build/windows-packaged-smoke.json"
$AppExe = Join-Path $ProjectRoot "dist/windows/HlgBridge/HlgBridge.exe"
$Process = Start-Process -FilePath $AppExe -ArgumentList @("--self-test", ('"' + $Report + '"')) -Wait -PassThru
if (Test-Path $Report) { Get-Content $Report -Raw | Write-Host }
$FaultReport = [System.IO.Path]::ChangeExtension($Report, ".fault.log")
if (Test-Path $FaultReport) { Get-Content $FaultReport -Raw | Write-Host }
if ($Process.ExitCode -ne 0 -or -not (Test-Path $Report)) { throw "Packaged app self-test failed." }
$Smoke = Get-Content $Report -Raw | ConvertFrom-Json
if (-not $Smoke.success) { throw "Packaged app self-test failed: $($Smoke.error)" }
Copy-Item Windows/使用说明.txt dist/windows/HlgBridge/使用说明.txt
$Version = & $PythonExe -c "from hlgbridge import __version__; print(__version__)"
if ($LASTEXITCODE -ne 0) { throw "Could not read package version." }
$Archive = "dist/HlgBridge-v$Version-Windows-x64.zip"
Compress-Archive -Path dist/windows/HlgBridge -DestinationPath $Archive -Force
Write-Host "Built: $Archive"
