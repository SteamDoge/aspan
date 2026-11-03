# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 ASpan contributors.
#requires -Version 7.0
param([string]$Flutter = '')
$ErrorActionPreference='Stop'
$script:SpanRoot=Split-Path -Parent $PSScriptRoot
$local=Join-Path $script:SpanRoot '.tools/toolchains.json'
$script:SpanConfig=if(Test-Path -LiteralPath $local){Get-Content -LiteralPath $local -Raw | ConvertFrom-Json}else{$null}
if(-not $Flutter){$Flutter=if($SpanConfig){$SpanConfig.flutter}else{(Get-Command flutter -ErrorAction SilentlyContinue).Source}}
if(-not(Test-Path -LiteralPath $Flutter)){throw 'Provide installed Flutter path via -Flutter or .tools/toolchains.json'}
$script:SpanFlutter=$Flutter
$script:SpanDart=Join-Path (Split-Path -Parent $Flutter) 'dart.bat'
$script:SpanClient=Join-Path $script:SpanRoot 'apps/aspan'
$hasher=[Security.Cryptography.SHA256]::Create()
try{$lockKey=([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($script:SpanClient.ToLowerInvariant())))).Replace('-','').Substring(0,24)}finally{$hasher.Dispose()}
$script:SpanMutex=[Threading.Mutex]::new($false,"Local\ASpan-$lockKey")
try{$entered=$script:SpanMutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$entered=$true}
if(-not $entered){$script:SpanMutex.Dispose();throw 'Another ASpan Flutter operation is active'}
function Invoke-Span { param([string]$Program,[Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments) & $Program @Arguments; if($LASTEXITCODE -ne 0){throw "$Program failed ($LASTEXITCODE)"} }
function Initialize-SpanPluginLinks {
    $pluginFile=Join-Path $script:SpanClient '.flutter-plugins-dependencies'
    if(-not(Test-Path -LiteralPath $pluginFile)){return}
    $plugins=Get-Content -LiteralPath $pluginFile -Raw | ConvertFrom-Json
    $links=Join-Path $script:SpanClient 'windows/flutter/ephemeral/.plugin_symlinks'
    New-Item -ItemType Directory -Path $links -Force | Out-Null
    foreach($plugin in $plugins.plugins.windows){
        if(-not(Test-Path -LiteralPath $plugin.path)){continue}
        $link=Join-Path $links $plugin.name
        $existing=Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
        if($existing -and $existing.LinkTarget -and [IO.Path]::GetFullPath($existing.LinkTarget) -ine [IO.Path]::GetFullPath($plugin.path)){
            if(-not($existing.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Expected a generated plugin junction'}
            Remove-Item -LiteralPath $link -Force
        }
        if(-not(Test-Path -LiteralPath $link)){New-Item -ItemType Junction -Path $link -Target $plugin.path | Out-Null}
    }
}
function Initialize-SpanPlugins {
    Push-Location $script:SpanClient
    try{
        Initialize-SpanPluginLinks
        & $script:SpanFlutter pub get --enforce-lockfile
        $pubCode=$LASTEXITCODE
        Initialize-SpanPluginLinks
        if($pubCode -ne 0){Invoke-Span $script:SpanFlutter @('pub','get','--enforce-lockfile')}
    }finally{Pop-Location}
}
