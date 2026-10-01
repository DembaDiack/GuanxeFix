<#
.SYNOPSIS
  Build a "wide" Guanxe sideload: unlock orientation, keep original resources, sign splits.

.DESCRIPTION
  InputDir must contain Play/split APKs including base + arm64 (+ optional dpi/lang splits).
  OutputDir receives signed APKs ready for: adb install-multiple *.apk
  Then on device: guanxe-fix --fix-libs-only

.EXAMPLE
  .\tools\make-wide-apk.ps1 -InputDir C:\Guanxe\2.2.9 -OutDir C:\Guanxe\2.2.9-wide
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$InputDir,

  [Parameter(Mandatory = $true)]
  [string]$OutDir,

  [string]$Orientation = "fullUser",

  [string]$ToolsDir = $(Join-Path $env:TEMP "apktools"),

  [switch]$SkipInstallHint
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$MergePy = Join-Path $PSScriptRoot "merge_wide_apk.py"
$Work = Join-Path $env:TEMP ("gx_wide_build_" + [guid]::NewGuid().ToString("N").Substring(0, 8))

function Ensure-Tool {
  param([string]$Name, [string]$Url, [string]$Dest)
  if (Test-Path $Dest) { return }
  New-Item -ItemType Directory -Force -Path (Split-Path $Dest) | Out-Null
  Write-Host "Downloading $Name ..."
  Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
}

function Find-BaseApk([string]$dir) {
  $cands = @(Get-ChildItem $dir -File -Filter "*.apk")
  $base = $cands | Where-Object { $_.Name -match '(?i)^(base|.*[^a-z]base[^a-z].*)\.apk$' -or $_.Name -eq 'base.apk' } | Select-Object -First 1
  if (-not $base) {
    # largest non-split often is base
    $base = $cands | Where-Object { $_.Name -notmatch '(?i)split_config|arm64|armeabi|x86|hdpi|xxhd|mdpi|\.en\.|\.es\.' } |
      Sort-Object Length -Descending | Select-Object -First 1
  }
  if (-not $base) { throw "No base.apk found in $dir" }
  return $base
}

Write-Host "== Guanxe wide APK builder =="
Write-Host "Input : $InputDir"
Write-Host "Output: $OutDir"
Write-Host "Work  : $Work"

if (-not (Test-Path $InputDir)) { throw "InputDir not found: $InputDir" }
if (-not (Test-Path $MergePy)) { throw "Missing $MergePy" }
$java = Get-Command java -ErrorAction SilentlyContinue
if (-not $java) { throw "Java not found on PATH" }

New-Item -ItemType Directory -Force -Path $Work, $OutDir, $ToolsDir | Out-Null
Ensure-Tool "apktool" "https://github.com/iBotPeaches/Apktool/releases/download/v2.11.1/apktool_2.11.1.jar" (Join-Path $ToolsDir "apktool.jar")
Ensure-Tool "uber-apk-signer" "https://github.com/patrickfav/uber-apk-signer/releases/download/v1.3.0/uber-apk-signer-1.3.0.jar" (Join-Path $ToolsDir "uber-apk-signer.jar")

$apktool = Join-Path $ToolsDir "apktool.jar"
$signer = Join-Path $ToolsDir "uber-apk-signer.jar"
$base = Find-BaseApk $InputDir
Write-Host "Using base: $($base.FullName)"

$decoded = Join-Path $Work "decoded"
$builtBad = Join-Path $Work "built-badres.apk"
$merged = Join-Path $Work "base-merged-unsigned.apk"
$signIn = Join-Path $Work "sign_in"
$signOut = Join-Path $Work "sign_out"
New-Item -ItemType Directory -Force -Path $signIn, $signOut | Out-Null

Write-Host "`n[1/5] apktool decode..."
& java -jar $apktool d -f -o $decoded $base.FullName
$manifest = Join-Path $decoded "AndroidManifest.xml"
if (-not (Test-Path $manifest)) { throw "AndroidManifest.xml missing after decode" }

Write-Host "[2/5] set screenOrientation=$Orientation"
$xml = Get-Content $manifest -Raw
if ($xml -notmatch 'screenOrientation=') {
  throw "No screenOrientation attribute found in manifest"
}
$xml2 = [regex]::Replace($xml, 'android:screenOrientation="[^"]+"', "android:screenOrientation=`"$Orientation`"")
# Write UTF-8 without BOM
$utf8 = New-Object System.Text.UTF8Encoding $false
[IO.File]::WriteAllText($manifest, $xml2, $utf8)

Write-Host "[3/5] apktool build (resources will be replaced next)..."
& java -jar $apktool b -o $builtBad $decoded

Write-Host "[4/5] merge original resources + keep META-INF/services..."
& python $MergePy --built $builtBad --original $base.FullName --out $merged

Write-Host "[5/5] collect splits + sign all with same key..."
Copy-Item $merged (Join-Path $signIn "base.apk") -Force
Get-ChildItem $InputDir -File -Filter "*.apk" | Where-Object { $_.FullName -ne $base.FullName } | ForEach-Object {
  Copy-Item $_.FullName (Join-Path $signIn $_.Name) -Force
}

& java -jar $signer --allowResign -a $signIn -o $signOut
Get-ChildItem $signOut -Filter "*.apk" | ForEach-Object {
  $destName = $_.Name -replace '-aligned-debugSigned$', '' -replace '-debugSigned$', ''
  if ($destName -notlike '*.apk') { $destName = "$destName.apk" }
  # Normalize base name
  if ($destName -match '(?i)base') { $destName = "base.apk" }
  Copy-Item $_.FullName (Join-Path $OutDir $destName) -Force
  Write-Host "  -> $destName"
}

Write-Host "`nDone. Signed APKs in: $OutDir"
if (-not $SkipInstallHint) {
  Write-Host @"

Install on WSA:
  adb connect 127.0.0.1:58526
  adb uninstall com.guanxe.guanxeprime
  adb install-multiple (Get-ChildItem '$OutDir\*.apk').FullName
  adb shell su -c 'guanxe-fix --fix-libs-only'
  adb shell wm set-ignore-orientation-request true
  adb shell am start -n com.guanxe.guanxeprime/.MainActivity

See HOWTO.md for details.
"@
}

# Cleanup workdir (keep OutDir)
Remove-Item $Work -Recurse -Force -ErrorAction SilentlyContinue
