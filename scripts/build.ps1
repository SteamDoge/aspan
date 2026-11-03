#requires -Version 7.0
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 ASpan contributors.
param(
    [ValidateSet('windows','android','all')][string]$Platform='windows',
    [ValidateSet('Debug','Release')][string]$Configuration='Release',
    [string]$Flutter='', [string]$AndroidSdk='', [string]$Java=''
)
. (Join-Path $PSScriptRoot 'environment.ps1') -Flutter $Flutter
$saved=@{}
$keys=@('JAVA_HOME','ANDROID_HOME','ANDROID_SDK_ROOT','TEMP','TMP','TMPDIR',
    'CC_aarch64_linux_android','AR_aarch64_linux_android','CC_x86_64_linux_android','AR_x86_64_linux_android',
    'CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER','CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER')
foreach($key in $keys){$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
Push-Location $SpanRoot
try {
    $package=(Get-Content (Join-Path $SpanClient 'pubspec.yaml') -Raw)
    if($package -notmatch '(?m)^version:\s*([^\s]+)\s*$'){throw 'Package version is missing'}
    $version=$matches[1]
    # An uncommitted checkout is useful for local builds, but is never a release.
    $sourceCommit='uncommitted'
    $committed=git rev-parse --verify HEAD 2>$null
    if($LASTEXITCODE -eq 0){
        $sourceCommit=$committed.Trim()
        $dirty=git status --porcelain
        if($LASTEXITCODE -ne 0){throw 'Cannot inspect source state'}
        if($dirty){$sourceCommit+='-modified'}
    }
    $mode=$Configuration.ToLowerInvariant()
    $cargoMode=if($Configuration -eq 'Release'){@('--release')}else{@()}
    Initialize-SpanPlugins
    if($Platform -in @('windows','all')){
        Invoke-Span cargo (@('build','-p','aspan-runtime','--locked')+$cargoMode)
        Push-Location $SpanClient
        try {
            Invoke-Span $SpanFlutter @('build','windows',"--$mode", "--dart-define=ASPAN_COMMIT=$sourceCommit", "--dart-define=ASPAN_VERSION=$version (local build)")
        } finally { Pop-Location }
        # Copy the installed MSVC redistributables, retaining the complete bundle.
        $bundle=Join-Path $SpanClient "build/windows/x64/runner/$Configuration"
        $vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
        if(-not(Test-Path -LiteralPath $vswhere)){throw 'Visual Studio C++ tools are required'}
        $vsRoot=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if($LASTEXITCODE -ne 0 -or -not $vsRoot){throw 'Visual Studio C++ tools were not found'}
        $redist=Get-ChildItem -LiteralPath (Join-Path $vsRoot 'VC/Redist/MSVC') -Directory |
            Where-Object Name -match '^\d+\.' | Sort-Object {[version]$_.Name} -Descending | Select-Object -First 1
        if(-not $redist){throw 'MSVC redistributables were not found'}
        $crt=Get-ChildItem -LiteralPath (Join-Path $redist.FullName 'x64') -Directory -Filter 'Microsoft.VC*.CRT' | Select-Object -First 1
        if(-not $crt){throw 'MSVC x64 CRT was not found'}
        foreach($dll in @('msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll')){
            Copy-Item -LiteralPath (Join-Path $crt.FullName $dll) -Destination $bundle
        }
        Write-Output "Windows bundle: $bundle"
    }
    if($Platform -in @('android','all')){
        if(-not $AndroidSdk -and $SpanConfig){$AndroidSdk=$SpanConfig.androidSdk}
        if(-not $Java -and $SpanConfig){$Java=$SpanConfig.java}
        if(-not $AndroidSdk -or -not $Java){throw 'Provide existing Android SDK and JDK paths'}
        if($Configuration -eq 'Release' -and -not(Test-Path -LiteralPath (Join-Path $SpanClient 'android/key.properties'))){
            throw 'Use your own ignored android/key.properties and signing keystore, or build Debug'
        }
        $env:ANDROID_HOME=$AndroidSdk; $env:ANDROID_SDK_ROOT=$AndroidSdk; $env:JAVA_HOME=$Java
        $ndk=Join-Path $AndroidSdk 'ndk/28.2.13676358/toolchains/llvm/prebuilt/windows-x86_64/bin'
        if(-not(Test-Path -LiteralPath $ndk)){throw 'Installed NDK 28.2.13676358 is required'}
        . (Join-Path $PSScriptRoot 'android-environment.ps1')
        $androidTarget=Initialize-SpanAndroidOutput -Path (Join-Path $SpanRoot 'target/android')
        $androidTemp=Join-Path $androidTarget ('tmp/'+[Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $androidTemp -Force | Out-Null
        $env:TEMP=$androidTemp; $env:TMP=$androidTemp; $env:TMPDIR=$androidTemp
        foreach($output in @('app','jni','jni_flutter','file_selector_android','path_provider_android','integration_test')){
            Initialize-SpanAndroidOutput -Path (Join-Path $SpanClient "build/$output") | Out-Null
        }
        Initialize-SpanAndroidOutput -Path (Join-Path $SpanClient 'android/.gradle') | Out-Null
        $nativeDir=Join-Path $androidTarget ('jniLibs/'+[Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $nativeDir | Out-Null
        foreach($abi in @(
            @{rust='aarch64-linux-android';clang='aarch64-linux-android24-clang.cmd';folder='arm64-v8a'},
            @{rust='x86_64-linux-android';clang='x86_64-linux-android24-clang.cmd';folder='x86_64'})){
            $key=$abi.rust.Replace('-','_'); $upper=$key.ToUpperInvariant()
            Set-Item -Path "Env:CC_$key" -Value (Join-Path $ndk $abi.clang)
            Set-Item -Path "Env:AR_$key" -Value (Join-Path $ndk 'llvm-ar.exe')
            Set-Item -Path "Env:CARGO_TARGET_${upper}_LINKER" -Value (Join-Path $ndk $abi.clang)
            Invoke-Span cargo (@('build','-p','aspan-runtime','--target',$abi.rust,'--target-dir',$androidTarget,'--locked')+$cargoMode)
            $jni=Join-Path $nativeDir $abi.folder
            New-Item -ItemType Directory -Path $jni -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $androidTarget "$($abi.rust)/$mode/libaspan_bridge.so") -Destination (Join-Path $jni 'libaspan_bridge.so')
        }
        Push-Location $SpanClient
        try {
            Invoke-Span $SpanFlutter @('build','apk',"--$mode",'--no-android-gradle-daemon',
                '--target-platform','android-arm64,android-x64','--split-per-abi',
                "--android-project-arg=aspan.nativeDir=$nativeDir",'--android-project-arg=kotlin.incremental=false',
                '--android-project-arg=kotlin.compiler.execution.strategy=in-process',
                "--dart-define=ASPAN_COMMIT=$sourceCommit", "--dart-define=ASPAN_VERSION=$version (local build)")
        } finally { Pop-Location }
        Write-Output "Android APKs: $(Join-Path $SpanClient 'build/app/outputs/flutter-apk')"
    }
} finally {
    foreach($key in $saved.Keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')}
    Pop-Location
    $SpanMutex.ReleaseMutex(); $SpanMutex.Dispose()
}
