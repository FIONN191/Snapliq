param([switch]$Installer)
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
cmake -S . -B .build/windows -A x64
if ($LASTEXITCODE) { throw "CMake configuration failed" }
cmake --build .build/windows --config Release
if ($LASTEXITCODE) { throw "Windows build failed" }
ctest --test-dir .build/windows -C Release --output-on-failure
if ($LASTEXITCODE) { throw "Core tests failed" }
New-Item -ItemType Directory -Force outputs/windows | Out-Null
Copy-Item .build/windows/apps/windows/Release/Snapliq.exe outputs/windows/Snapliq.exe
Write-Host "Built unsigned Windows development executable; real desktop validation is still required."

if ($Installer) {
    $brand = Get-Content brand/product.json -Raw | ConvertFrom-Json
    $iscc = Get-Command ISCC.exe -ErrorAction Stop
    & $iscc.Source "/DAppVersion=$($brand.version)" "/DAppName=$($brand.desktopName)" packaging/windows/Snapliq.iss
    if ($LASTEXITCODE) { throw "Installer compilation failed" }
}
