#requires -Version 7.0
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 ASpan contributors.
param([ValidateSet('windows','android','all')][string]$Platform='all',[string]$Flutter='', [string]$AndroidSdk='', [string]$Java='', [string]$BuildTag='')
. (Join-Path $PSScriptRoot 'environment.ps1') -Flutter $Flutter
$saved=@{};foreach($key in @('JAVA_HOME','ANDROID_HOME','ANDROID_SDK_ROOT','TEMP','TMP','TMPDIR','CC_aarch64_linux_android','AR_aarch64_linux_android','CC_x86_64_linux_android','AR_x86_64_linux_android','CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER','CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER')){$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
Push-Location $SpanRoot
try{
    $dirty=git status --porcelain
    if($LASTEXITCODE -ne 0 -or $dirty){throw 'Commit integrated source before building a delivery'}
    $commit=git rev-parse HEAD;if($LASTEXITCODE -ne 0){throw 'A committed source baseline is required'}
    $gitDir=(git rev-parse --absolute-git-dir).Trim()
    if([IO.Path]::GetFullPath($gitDir) -ine (Join-Path $SpanRoot '.git')){throw 'Build releases from the primary checkout, not a linked worktree'}
    $pubspec=Get-Content -LiteralPath (Join-Path $SpanClient 'pubspec.yaml') -Raw
    if($pubspec -notmatch '(?m)^version: (([0-9]+\.[0-9]+\.[0-9]+)-rc\.1)\+([1-9][0-9]*)\s*$'){throw 'Expected a committed RC package version and build number in pubspec.yaml'}
    $packageVersion=$matches[1];$version="rc$($matches[2])";$buildNumber=[int]$matches[3]
    $expectedTag="$version-build.$buildNumber"
    if(-not $BuildTag){$BuildTag=$expectedTag}
    if($BuildTag -ne $expectedTag){throw "BuildTag must equal $expectedTag"}
    $cargoVersion=Get-Content -LiteralPath (Join-Path $SpanRoot 'Cargo.toml') -Raw
    if($cargoVersion -notmatch "(?m)^version = `"$([regex]::Escape($packageVersion))`"\s*$"){throw 'Release version differs from Cargo.toml'}
    $tag=git rev-parse --verify "refs/tags/$BuildTag^{commit}" 2>$null
    if($LASTEXITCODE -ne 0 -or $tag -ne $commit){throw "Tag $BuildTag must point to the committed source before building"}
    $short=$commit.Substring(0,12)
    $destination=Join-Path $SpanRoot "deliveries/$version-$short-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
    if(Test-Path -LiteralPath $destination){throw 'Delivery directory already exists'}
    $finalDestination=$destination
    $destination=Join-Path $SpanRoot "deliveries/.pending-$version-$short-$([Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $destination | Out-Null
    @{status='building';commit=$commit;tag=$BuildTag} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destination 'build-status.json') -Encoding utf8
    Initialize-SpanPlugins
    $files=@()
    if($Platform -in @('windows','all')){
        Invoke-Span cargo @('build','-p','aspan-runtime','--release','--locked')
        Push-Location $SpanClient
        try{Invoke-Span $SpanFlutter @('build','windows','--release',"--dart-define=ASPAN_COMMIT=$commit","--dart-define=ASPAN_VERSION=$version (build.$buildNumber)")}finally{Pop-Location}
        $bundle=Join-Path $SpanClient 'build/windows/x64/runner/Release'
        $vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
        if(-not(Test-Path -LiteralPath $vswhere)){throw 'Existing Visual Studio installer vswhere is required'}
        $vsRoot=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if($LASTEXITCODE -ne 0 -or -not $vsRoot){throw 'Visual Studio C++ tools were not found'}
        $redist=Get-ChildItem -LiteralPath (Join-Path $vsRoot 'VC/Redist/MSVC') -Directory | Where-Object {$_.Name -match '^\d+\.'} | Sort-Object {[version]$_.Name} -Descending | Select-Object -First 1
        if(-not $redist){throw 'MSVC redistributable directory missing'}
        $crt=Get-ChildItem -LiteralPath (Join-Path $redist.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' | Select-Object -First 1
        if(-not $crt){throw 'MSVC x64 CRT directory missing'}
        $crtEvidence=@()
        foreach($dll in @('msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll')){ $file=Join-Path $crt.FullName $dll; Copy-Item -LiteralPath $file -Destination $bundle; $crtEvidence+=@{name=$dll;version=(Get-Item -LiteralPath $file).VersionInfo.FileVersion;sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()} }
        $zip=Join-Path $destination "ASpan-$version-windows-x64.zip"
        Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $zip
        $files+=Get-Item -LiteralPath $zip
    }
    if($Platform -in @('android','all')){
        if(-not $AndroidSdk -and $SpanConfig){$AndroidSdk=$SpanConfig.androidSdk}
        if(-not $Java -and $SpanConfig){$Java=$SpanConfig.java}
        if(-not $AndroidSdk -or -not $Java){throw 'Provide existing Android SDK and JDK paths; no SDKs are installed by this script'}
        if(-not(Test-Path -LiteralPath (Join-Path $SpanClient 'android/key.properties'))){throw 'Independent ASpan release signing is required in ignored android/key.properties'}
        $env:ANDROID_HOME=$AndroidSdk;$env:ANDROID_SDK_ROOT=$AndroidSdk;$env:JAVA_HOME=$Java
        $ndk=Join-Path $AndroidSdk 'ndk/28.2.13676358/toolchains/llvm/prebuilt/windows-x86_64/bin'
        if(-not(Test-Path -LiteralPath $ndk)){throw 'Existing NDK 28.2.13676358 required'}
        . (Join-Path $PSScriptRoot 'android-environment.ps1')
        $androidTarget=Initialize-SpanAndroidOutput -Path (Join-Path $SpanRoot 'target/android')
        $androidTemp=Join-Path $androidTarget ('tmp/'+[Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $androidTemp -Force | Out-Null
        $env:TEMP=$androidTemp;$env:TMP=$androidTemp;$env:TMPDIR=$androidTemp
        foreach($output in @('app','jni','jni_flutter','file_selector_android','path_provider_android','integration_test')) {
            Initialize-SpanAndroidOutput -Path (Join-Path $SpanClient "build/$output") | Out-Null
        }
        Initialize-SpanAndroidOutput -Path (Join-Path $SpanClient 'android/.gradle') | Out-Null
        $nativeDir=Join-Path $androidTarget ('jniLibs/'+$commit+'-'+[Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $nativeDir | Out-Null
        $toolEvidence=@{}
        foreach($name in @('clang.exe','ld.lld.exe','llvm-strip.exe','llvm-ar.exe')){$path=Join-Path $ndk $name;$toolEvidence[$name]=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
        foreach($abi in @(@{rust='aarch64-linux-android';clang='aarch64-linux-android24-clang.cmd';folder='arm64-v8a'},@{rust='x86_64-linux-android';clang='x86_64-linux-android24-clang.cmd';folder='x86_64'})){
            $key=$abi.rust.Replace('-','_');$upper=$key.ToUpperInvariant()
            Set-Item -Path "Env:CC_$key" -Value (Join-Path $ndk $abi.clang)
            Set-Item -Path "Env:AR_$key" -Value (Join-Path $ndk 'llvm-ar.exe')
            Set-Item -Path "Env:CARGO_TARGET_${upper}_LINKER" -Value (Join-Path $ndk $abi.clang)
            Invoke-Span cargo @('build','-p','aspan-runtime','--target',$abi.rust,'--target-dir',$androidTarget,'--release','--locked')
            $jni=Join-Path $nativeDir $abi.folder;New-Item -ItemType Directory -Path $jni -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $androidTarget "$($abi.rust)/release/libaspan_bridge.so") -Destination (Join-Path $jni 'libaspan_bridge.so')
        }
        Push-Location $SpanClient
        # Avoid cross-drive incremental caches and stale Kotlin daemon maps when
        # reusing an existing Pub cache. Explicit -P arguments also override
        # defaults supplied by the Flutter/Gradle build tooling. A single-use
        # Gradle JVM must exit before this build owns and removes its TEMP directory.
        try{Invoke-Span $SpanFlutter @('build','apk','--release','--no-android-gradle-daemon','--target-platform','android-arm64,android-x64','--split-per-abi',"--android-project-arg=aspan.nativeDir=$nativeDir",'--android-project-arg=kotlin.incremental=false','--android-project-arg=kotlin.compiler.execution.strategy=in-process',"--dart-define=ASPAN_COMMIT=$commit","--dart-define=ASPAN_VERSION=$version (build.$buildNumber)")}finally{Pop-Location}
        foreach($name in $toolEvidence.Keys){if((Get-FileHash -LiteralPath (Join-Path $ndk $name) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $toolEvidence[$name]){throw 'NDK tool changed during build'}}
        foreach($abi in @('arm64-v8a','x86_64')){$source=Join-Path $SpanClient "build/app/outputs/flutter-apk/app-$abi-release.apk";$dest=Join-Path $destination "ASpan-$version-android-$abi.apk";Copy-Item -LiteralPath $source -Destination $dest;$files+=Get-Item -LiteralPath $dest}
    }
    $dirty=git status --porcelain
    if($LASTEXITCODE -ne 0 -or $dirty -or (git rev-parse HEAD) -ne $commit){throw 'Source changed during build; do not deliver these artifacts'}
    $flutterVersion=(& $SpanFlutter --version | Out-String).Trim();if($LASTEXITCODE -ne 0){throw 'Flutter version probe failed'}
    $rustVersion=(& rustc --version | Out-String).Trim();if($LASTEXITCODE -ne 0){throw 'Rust version probe failed'}
    $cargoVersion=(& cargo --version | Out-String).Trim();if($LASTEXITCODE -ne 0){throw 'Cargo version probe failed'}
    $javaVersion=$null;if($Java){$javaVersion=(& (Join-Path $Java 'bin/java.exe') --version | Out-String).Trim();if($LASTEXITCODE -ne 0){throw 'JDK version probe failed'}}
    $manifest=[ordered]@{version=$version;package_version=$packageVersion;build_number=$buildNumber;tag=$BuildTag;kind='release-candidate';commit=$commit;platform=$Platform;built_at=(Get-Date).ToString('o');flutter=$flutterVersion;rust=$rustVersion;cargo=$cargoVersion;java=$javaVersion;ndk='28.2.13676358';gradle_wrapper=(Get-Content (Join-Path $SpanClient 'android/gradle/wrapper/gradle-wrapper.properties') -Raw);android_plugins=(Get-Content (Join-Path $SpanClient 'android/settings.gradle.kts') -Raw);crt=$crtEvidence;ndk_tools=$toolEvidence;android_integrity='Shared NDK/SDK and disposable Android outputs retain existing Low integrity; tool hashes detect changes during this build, not pre-existing compromise';host=[Environment]::OSVersion.VersionString;validation='Static package verification only (verification-package.json); build success is not runtime acceptance';android_signing='Independent ASpan release certificate; see verification-package.json';windows_signing='Unsigned portable ZIP';artifacts=@($files|ForEach-Object{@{name=$_.Name;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})}
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $destination 'manifest.json') -Encoding utf8
    $verifyArgs=@((Join-Path $PSScriptRoot 'verify-release.py'),$destination)
    if($Platform -in @('android','all')){$verifyArgs+=@('--sdk',$AndroidSdk,'--java',$Java)}
    Invoke-Span python $verifyArgs
    @{status='verified';commit=$commit;tag=$BuildTag} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destination 'build-status.json') -Encoding utf8
    $deliveryRoot=[IO.Path]::GetFullPath((Join-Path $SpanRoot 'deliveries')).TrimEnd('\')+'\'
    if(-not([IO.Path]::GetFullPath($destination).StartsWith($deliveryRoot,[StringComparison]::OrdinalIgnoreCase)) -or -not([IO.Path]::GetFullPath($finalDestination).StartsWith($deliveryRoot,[StringComparison]::OrdinalIgnoreCase))){throw 'Delivery move escaped workspace'}
    Move-Item -LiteralPath $destination -Destination $finalDestination
    Write-Output "Delivery: $finalDestination"
}catch{
    if($destination -and (Test-Path -LiteralPath $destination)){
        @{status='failed';commit=$commit;message=$_.Exception.Message} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $destination 'build-status.json') -Encoding utf8
    }
    throw
}finally{
    try {
    if($androidTemp -and (Test-Path -LiteralPath $androidTemp)){
        $expectedPrefix=[IO.Path]::GetFullPath((Join-Path $SpanRoot 'target/android/tmp')).TrimEnd('\')+'\'
        if(-not([IO.Path]::GetFullPath($androidTemp).StartsWith($expectedPrefix,[StringComparison]::OrdinalIgnoreCase))){throw 'Temporary cleanup escaped build output'}
        if((Get-Item -LiteralPath $androidTemp -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Refuse linked temporary output'}
        if(Get-ChildItem -LiteralPath $androidTemp -Recurse -Force -Attributes ReparsePoint){throw 'Refuse linked temporary descendants'}
        Remove-Item -LiteralPath $androidTemp -Recurse -Force
    }
    } finally {
        foreach($key in $saved.Keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')};Pop-Location;$SpanMutex.ReleaseMutex();$SpanMutex.Dispose()
    }
}
