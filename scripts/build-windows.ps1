param([switch]$Installer, [switch]$VerifyInstaller)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
Set-Location (Join-Path $PSScriptRoot "..")
if ($env:OS -ne "Windows_NT") { throw "Build this package on Windows with Visual Studio 2022 and the Windows SDK." }
if ($VerifyInstaller -and -not $Installer) { throw "-VerifyInstaller requires -Installer." }

$brand = Get-Content brand/product.json -Raw | ConvertFrom-Json
$version = [string]$brand.version
$packageName = "Snapliq-$version-windows-x64-development"
$outputDir = Join-Path (Get-Location) "outputs/windows"
New-Item -ItemType Directory -Force $outputDir | Out-Null

cmake -S . -B .build/windows -A x64
if ($LASTEXITCODE -ne 0) { throw "CMake configuration failed ($LASTEXITCODE)." }
cmake --build .build/windows --config Release
if ($LASTEXITCODE -ne 0) { throw "Windows build failed ($LASTEXITCODE)." }
ctest --test-dir .build/windows -C Release --verbose
if ($LASTEXITCODE -ne 0) { throw "Windows tests failed ($LASTEXITCODE)." }

$exe = Join-Path $outputDir "Snapliq.exe"
Copy-Item .build/windows/apps/windows/Release/Snapliq.exe $exe -Force
$fileVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
if ($fileVersion.ProductVersion -ne $version) { throw "Executable product version '$($fileVersion.ProductVersion)' does not match $version." }
$exeHash = (Get-FileHash -Algorithm SHA256 $exe).Hash
$readme = Join-Path $outputDir "README.zh-CN.txt"
(Get-Content packaging/windows/README.zh-CN.txt -Raw).Replace("@VERSION@", $version) | Set-Content -Encoding utf8 $readme

# Portable mode shares the existing per-user preferences and save folder.
$stage = Join-Path (Get-Location) ".build/windows/package/$packageName"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item $exe, $readme $stage
$portable = Join-Path $outputDir "$packageName-portable.zip"
Compress-Archive -Path $stage -DestinationPath $portable -Force
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($portable)
try {
    $entry = $archive.GetEntry("$packageName/Snapliq.exe")
    if ($null -eq $entry -or $null -eq $archive.GetEntry("$packageName/README.zh-CN.txt")) { throw "Portable archive is missing the executable or instructions." }
    $stream = $entry.Open()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $archiveHash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace("-", "") }
    finally { $stream.Dispose(); $sha.Dispose() }
    if ($archiveHash -ne $exeHash) { throw "Portable executable hash differs from the compiled executable." }
} finally { $archive.Dispose() }
$artifacts = @($exe, $readme, $portable)

if ($Installer) {
    $iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    $isccPath = if ($null -ne $iscc) { $iscc.Source } else { $null }
    if (-not $isccPath) {
        foreach ($candidate in @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe")) {
            if (Test-Path $candidate) { $isccPath = $candidate; break }
        }
    }
    if (-not $isccPath) { throw "Inno Setup 6 was not found. Install it from https://jrsoftware.org/isdl.php, then rerun with -Installer." }
    & $isccPath "/DAppVersion=$version" "/DAppName=$($brand.desktopName)" packaging/windows/Snapliq.iss
    if ($LASTEXITCODE -ne 0) { throw "Installer compilation failed ($LASTEXITCODE)." }
    $setup = Join-Path $outputDir "$packageName-setup.exe"
    if (-not (Test-Path $setup)) { throw "Expected installer was not produced: $setup" }
    $artifacts += $setup

    if ($VerifyInstaller) {
        # Do not exercise the real AppId on a developer's installed copy.
        if ($env:GITHUB_ACTIONS -ne "true" -or -not $env:RUNNER_TEMP) { throw "Installer smoke validation is restricted to a clean GitHub Actions runner." }
        foreach ($key in @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Snapliq.Development_is1", "HKCU:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Snapliq.Development_is1")) {
            if (Test-Path $key) { throw "Refusing to replace an existing Snapliq install during validation." }
        }
        $installDir = Join-Path $env:RUNNER_TEMP ("snapliq-install-test-" + [Guid]::NewGuid().ToString("N"))
        $diagnostics = Join-Path $outputDir "diagnostics"
        New-Item -ItemType Directory -Force $diagnostics | Out-Null
        $installedExe = Join-Path $installDir "Snapliq.exe"
        $uninstaller = Join-Path $installDir "unins000.exe"
        try {
            $installLog = Join-Path $diagnostics "install.log"
            $process = Start-Process -FilePath $setup -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/NOICONS', '/NOCLOSEAPPLICATIONS', '/NORESTARTAPPLICATIONS', "/DIR=`"$installDir`"", "/LOG=`"$installLog`"") -PassThru -Wait
            if ($process.ExitCode -ne 0) { throw "Silent installation failed ($($process.ExitCode))." }
            if (-not (Test-Path $installedExe)) { throw "Installed Snapliq.exe is missing." }
            if ((Get-FileHash -Algorithm SHA256 $installedExe).Hash -ne $exeHash) { throw "Installed executable hash differs from the compiled executable." }
            if ([System.Diagnostics.FileVersionInfo]::GetVersionInfo($installedExe).ProductVersion -ne $version) { throw "Installed executable version is incorrect." }
            if (-not (Test-Path (Join-Path $installDir "README.zh-CN.txt"))) { throw "Installed instructions are missing." }
        } finally {
            if (Test-Path $uninstaller) {
                $uninstallLog = Join-Path $diagnostics "uninstall.log"
                $process = Start-Process -FilePath $uninstaller -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=`"$uninstallLog`"") -PassThru -Wait
                if ($process.ExitCode -ne 0) { throw "Silent uninstall failed ($($process.ExitCode))." }
            }
        }
        if (Test-Path $installedExe) { throw "Uninstall left the executable behind." }
        [ordered]@{
            version = $version
            executableSHA256 = $exeHash.ToLowerInvariant()
            installerInstallAndUninstall = "passed"
            portablePayloadHash = "passed"
            desktopCaptureAndAudio = "not tested by this workflow"
        } | ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $diagnostics "package-validation.json")
    }
}

$artifacts | ForEach-Object {
    "{0}  {1}" -f (Get-FileHash -Algorithm SHA256 $_).Hash.ToLowerInvariant(), [IO.Path]::GetFileName($_)
} | Set-Content -Encoding ascii (Join-Path $outputDir "SHA256SUMS.txt")
Write-Host "Built Snapliq $version for Windows 10 2004 (19041)+ / Windows 11 x64."
Write-Host "Unsigned development packages: $outputDir"
Write-Host "Compilation and packaging validation do not establish real desktop capture or audio results."
