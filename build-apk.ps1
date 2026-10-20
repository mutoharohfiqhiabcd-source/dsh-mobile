# DSH Mobile APK build script
#
# Build chain (no Gradle):
#   aapt2 compile -> aapt2 link -> javac -> d8 -> append classes.dex + rootfs
#   -> zipalign -> apksigner
#
# Why no Gradle: the app must target SDK 28 so Android still allows executing
# binaries and dlopen()ing libraries from the app-private data dir (the trick
# Termux uses). Keeping the whole pipeline explicit also avoids AGP version
# drift; only JDK + Android build-tools are needed.
#
# NOTE: keep this file ASCII-only. PowerShell 5.1 mis-decodes UTF-8-without-BOM
#       and can swallow quotes inside non-ASCII comments, breaking parsing.
#
# Layout expected next to this script:
#   apk/AndroidManifest.xml, apk/src, apk/res, apk/assets
#   apk/assets/runtime/            (from scripts/fetch-runtime.sh)
#   apk/assets/overlay/            (from scripts/fetch-overlay.sh, optional)
#   apk/rootfs-asset/rootfs.tar.gz (the bundled Debian+DSH rootfs)
#   android-tools/                 (JDK 17 + Android SDK build-tools + platform)
# Output: dist/DSH-Mobile.apk

param(
  [string]$VersionCode = $(if ($env:DSH_VERSION_CODE) { $env:DSH_VERSION_CODE } else { '1' }),
  [string]$VersionName = $(if ($env:DSH_VERSION_NAME) { $env:DSH_VERSION_NAME } else { '1.0' })
)

$ErrorActionPreference = 'Stop'

$root   = $PSScriptRoot
$tools  = Join-Path $root 'android-tools'
$jdkDir = if ($env:DSH_JDK) { $env:DSH_JDK } else { (Get-ChildItem (Join-Path $tools 'jdk17') -Directory -ErrorAction SilentlyContinue | Select-Object -First 1).FullName }
$sdk    = if ($env:DSH_SDK) { $env:DSH_SDK } else { Join-Path $tools 'sdk' }
$bt     = Join-Path $sdk 'build-tools\34.0.0'
$aj     = Join-Path $sdk 'platforms\android-34\android.jar'
$proj   = Join-Path $root 'apk'
$build  = Join-Path $proj 'build'
$dist   = Join-Path $root 'dist'
$outApk = Join-Path $dist 'DSH-Mobile.apk'
$ks     = if ($env:DSH_KEYSTORE) { $env:DSH_KEYSTORE } else { Join-Path $root 'release.jks' }

$env:JAVA_HOME = $jdkDir
$env:PATH = (Join-Path $jdkDir 'bin') + ';' + $env:PATH

function Step([string]$name) { Write-Host ("`n=== " + $name + " ===") -ForegroundColor Cyan }
function Need([string]$path, [string]$label) { if (-not (Test-Path $path)) { throw ("missing " + $label + ": " + $path) } }
function Run([string]$exe, [string[]]$params, [string]$label) {
  & $exe @params
  if ($LASTEXITCODE -ne 0) { throw ($label + ' failed (exit ' + $LASTEXITCODE + ')') }
}

Need $jdkDir 'JDK 17'
Need $aj 'android.jar'
Need (Join-Path $bt 'aapt2.exe') 'aapt2'
Need (Join-Path $bt 'd8.bat') 'd8'
Need (Join-Path $bt 'zipalign.exe') 'zipalign'
Need (Join-Path $bt 'apksigner.bat') 'apksigner'
Need (Join-Path $proj 'assets\runtime\proot') 'proot asset (run scripts/fetch-runtime.sh)'
Need (Join-Path $proj 'assets\runtime\loader') 'proot loader asset'

Step '0. clean'
Remove-Item $build -Recurse -Force -ErrorAction SilentlyContinue
foreach ($d in 'gen','classes','dex') { New-Item -ItemType Directory -Force -Path (Join-Path $build $d) | Out-Null }
New-Item -ItemType Directory -Force -Path $dist | Out-Null

Step '1. aapt2 compile'
Run (Join-Path $bt 'aapt2.exe') @('compile','--dir',(Join-Path $proj 'res'),'-o',(Join-Path $build 'res.zip')) 'aapt2 compile'

Step '2. aapt2 link (assets + targetSdk 28)'
Run (Join-Path $bt 'aapt2.exe') @(
  'link','-o',(Join-Path $build 'base.apk'),
  '-I',$aj,
  '--manifest',(Join-Path $proj 'AndroidManifest.xml'),
  '-R',(Join-Path $build 'res.zip'),
  '-A',(Join-Path $proj 'assets'),
  '--java',(Join-Path $build 'gen'),
  '--min-sdk-version','26','--target-sdk-version','28',
  '--version-code',$VersionCode,'--version-name',$VersionName,
  '--auto-add-overlay'
) 'aapt2 link'

Step '3. javac'
$srcs = @()
$srcs += (Get-ChildItem (Join-Path $proj 'src') -Recurse -Filter *.java | ForEach-Object { $_.FullName })
$srcs += (Get-ChildItem (Join-Path $build 'gen') -Recurse -Filter *.java | ForEach-Object { $_.FullName })
$jcArgs = @()
$jcArgs += '-encoding'; $jcArgs += 'UTF-8'
$jcArgs += '-source';   $jcArgs += '8'
$jcArgs += '-target';   $jcArgs += '8'
$jcArgs += '-nowarn'
$jcArgs += '-classpath'; $jcArgs += $aj
$jcArgs += '-d';        $jcArgs += (Join-Path $build 'classes')
$jcArgs += $srcs
Run (Join-Path $jdkDir 'bin\javac.exe') $jcArgs 'javac'
Write-Host ('class files: ' + (Get-ChildItem (Join-Path $build 'classes') -Recurse -Filter *.class | Measure-Object).Count)

Step '4. d8'
Run (Join-Path $jdkDir 'bin\jar.exe') @('cf',(Join-Path $build 'classes.jar'),'-C',(Join-Path $build 'classes'),'.') 'jar'
Run (Join-Path $bt 'd8.bat') @(
  '--lib',$aj,'--min-api','26','--output',(Join-Path $build 'dex'),
  (Join-Path $build 'classes.jar')
) 'd8'
Need (Join-Path $build 'dex\classes.dex') 'classes.dex'
Write-Host ('classes.dex: ' + [math]::Round((Get-Item (Join-Path $build 'dex\classes.dex')).Length/1KB,1) + ' KB')

Step '5. add classes.dex'
$pyFile = Join-Path $build 'add_dex.py'
$pyCode = @'
import sys, zipfile
apk, dex = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(apk, 'a', zipfile.ZIP_DEFLATED) as z:
    z.write(dex, 'classes.dex')
print('classes.dex added')
'@
Set-Content -Path $pyFile -Value $pyCode -Encoding ASCII
Run 'python' @($pyFile,(Join-Path $build 'base.apk'),(Join-Path $build 'dex\classes.dex')) 'add dex'

Step '5.5 append bundled rootfs (ZIP_STORED, streamed)'
# aapt2 would deflate a 900 MB asset (slow, pointless); append it ourselves stored.
$rootfsAsset = Join-Path $proj 'rootfs-asset\rootfs.tar.gz'
if (Test-Path $rootfsAsset) {
  $py2 = Join-Path $build 'add_rootfs.py'
  $py2Code = @'
import sys, zipfile, os, shutil
apk, f = sys.argv[1], sys.argv[2]
zi = zipfile.ZipInfo('assets/rootfs.tar.gz', date_time=(2026, 1, 1, 0, 0, 0))
zi.compress_type = zipfile.ZIP_STORED
zi.file_size = os.path.getsize(f)
with zipfile.ZipFile(apk, 'a', zipfile.ZIP_STORED) as z, open(f, 'rb') as src, z.open(zi, 'w') as dst:
    shutil.copyfileobj(src, dst, 1 << 20)
print('rootfs appended', os.path.getsize(f))
'@
  Set-Content -Path $py2 -Value $py2Code -Encoding ASCII
  Run 'python' @($py2,(Join-Path $build 'base.apk'),$rootfsAsset) 'append rootfs'
} else {
  Write-Host '  (no rootfs asset — APK will need an imported rootfs.tar.gz at runtime)'
}

Step '6. zipalign'
Run (Join-Path $bt 'zipalign.exe') @('-f','-p','4',(Join-Path $build 'base.apk'),(Join-Path $build 'aligned.apk')) 'zipalign'

Step '7. sign'
if (-not (Test-Path $ks)) {
  Write-Host '  generating a local release keystore (release.jks, password dshmobile)'
  Run (Join-Path $jdkDir 'bin\keytool.exe') @(
    '-genkeypair','-keystore',$ks,'-alias','dsh','-keyalg','RSA','-keysize','2048',
    '-validity','10000','-storepass','dshmobile','-keypass','dshmobile',
    '-dname','CN=DSH Mobile, OU=DSH, O=DSH, L=Local, ST=Local, C=CN'
  ) 'keytool'
}
Run (Join-Path $bt 'apksigner.bat') @(
  'sign','--ks',$ks,'--ks-pass','pass:dshmobile','--key-pass','pass:dshmobile',
  '--out',$outApk,(Join-Path $build 'aligned.apk')
) 'apksigner'

Step '8. verify'
& (Join-Path $bt 'apksigner.bat') verify --print-certs $outApk
& (Join-Path $bt 'aapt2.exe') dump badging $outApk

$item = Get-Item $outApk
Write-Host ("`nAPK: " + $item.FullName + "  " + [math]::Round($item.Length/1MB,1) + " MB") -ForegroundColor Green
