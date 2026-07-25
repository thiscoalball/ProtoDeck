param(
  [Parameter(Mandatory = $true)]
  [Alias('ReleaseDirectory')]
  [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$iperfVersion = '3.21'
$cygwinVersion = '3.6.7-1'
$iperfArchiveName = "iperf-$iperfVersion-win64.zip"
$cygwinSourceName = "cygwin-$cygwinVersion-src.tar.xz"
$iperfUrl = "https://github.com/ar51an/iperf3-win-builds/releases/download/$iperfVersion/$iperfArchiveName"
$cygwinSourceUrl = "https://ftp.fau.de/cygwin/src/release/cygwin/$cygwinSourceName"
$iperfSha256 = '9b73b7e0e0326347b5f4ac4f6a1fc34fe60a5966e5fd172c7bfcd0e1cc93e709'
$cygwinSourceSha512 = '82a190c3516511af7d1305e1bcd4aa0177c1fb584b6468a887a9119565bccd88630b2a3b826d902983a83adefb11545346dcf27616186304d6c66879e1647335'

$appRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $appRoot
$cacheDirectory = Join-Path $repositoryRoot '.tooling/iperf-windows-3.21'
$outputPath = [System.IO.Path]::GetFullPath((Join-Path $appRoot $OutputDirectory))
$iperfArchive = Join-Path $cacheDirectory $iperfArchiveName
$cygwinSourceArchive = Join-Path $cacheDirectory $cygwinSourceName
$extractDirectory = Join-Path $cacheDirectory 'runtime'

function Get-VerifiedDownload {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][ValidateSet('SHA256', 'SHA512')][string]$Algorithm,
    [Parameter(Mandatory = $true)][string]$ExpectedHash
  )

  if (Test-Path -LiteralPath $Destination) {
    $existingHash = (Get-FileHash -LiteralPath $Destination -Algorithm $Algorithm).Hash.ToLowerInvariant()
    if ($existingHash -eq $ExpectedHash) {
      return
    }
  }

  $downloadPath = "$Destination.download"
  Invoke-WebRequest -Uri $Url -OutFile $downloadPath
  $actualHash = (Get-FileHash -LiteralPath $downloadPath -Algorithm $Algorithm).Hash.ToLowerInvariant()
  if ($actualHash -ne $ExpectedHash) {
    throw "Checksum mismatch for $Url. Expected $ExpectedHash, got $actualHash."
  }
  Move-Item -LiteralPath $downloadPath -Destination $Destination -Force
}

New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null

Get-VerifiedDownload -Url $iperfUrl -Destination $iperfArchive `
  -Algorithm SHA256 -ExpectedHash $iperfSha256
Get-VerifiedDownload -Url $cygwinSourceUrl -Destination $cygwinSourceArchive `
  -Algorithm SHA512 -ExpectedHash $cygwinSourceSha512

if (Test-Path -LiteralPath $extractDirectory) {
  Remove-Item -LiteralPath $extractDirectory -Recurse -Force
}
Expand-Archive -LiteralPath $iperfArchive -DestinationPath $extractDirectory

$iperfExecutable = Join-Path $extractDirectory 'iperf3.exe'
$cygwinRuntime = Join-Path $extractDirectory 'cygwin1.dll'
if (-not (Test-Path -LiteralPath $iperfExecutable) -or
    -not (Test-Path -LiteralPath $cygwinRuntime)) {
  throw 'The verified iPerf archive does not contain iperf3.exe and cygwin1.dll.'
}

Copy-Item -LiteralPath $iperfExecutable -Destination (Join-Path $outputPath 'iperf3.exe') -Force
Copy-Item -LiteralPath $cygwinRuntime -Destination (Join-Path $outputPath 'cygwin1.dll') -Force

$licensesDirectory = Join-Path $outputPath 'licenses'
$sourceDirectory = Join-Path $licensesDirectory 'source'
New-Item -ItemType Directory -Path $sourceDirectory -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $appRoot 'android/app/src/main/cpp/iperf/LICENSE') `
  -Destination (Join-Path $licensesDirectory 'iperf3-LICENSE.txt') -Force
Copy-Item -LiteralPath (Join-Path $appRoot 'third_party/iperf3-windows-NOTICE.txt') `
  -Destination (Join-Path $licensesDirectory 'iperf3-windows-NOTICE.txt') -Force
Copy-Item -LiteralPath $cygwinSourceArchive `
  -Destination (Join-Path $sourceDirectory $cygwinSourceName) -Force

& (Join-Path $outputPath 'iperf3.exe') --version
if ($LASTEXITCODE -ne 0) {
  throw "Bundled iperf3.exe smoke test failed with exit code $LASTEXITCODE."
}

Write-Host "Bundled iPerf $iperfVersion and Cygwin runtime $cygwinVersion in $outputPath"
