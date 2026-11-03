# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 ASpan contributors.
#requires -Version 7.0
param([string]$Flutter='')
. (Join-Path $PSScriptRoot 'environment.ps1') -Flutter $Flutter
$previousLib=$env:ASPAN_RUST_LIB
Push-Location $SpanRoot
try{
    Invoke-Span cargo @('fmt','--all','--','--check')
    Invoke-Span cargo @('test','--workspace','--locked')
    Invoke-Span cargo @('clippy','--workspace','--all-targets','--locked','--','-D','warnings')
    Invoke-Span cargo @('build','-p','aspan-runtime','--locked')
    $env:ASPAN_RUST_LIB=Join-Path $SpanRoot 'target/debug/aspan_bridge.dll'
    Initialize-SpanPlugins
    Push-Location $SpanClient
    try{
        Invoke-Span $SpanDart @('format','--output=none','--set-exit-if-changed','lib','test','integration_test')
        Invoke-Span $SpanFlutter @('analyze')
        Invoke-Span $SpanFlutter @('test')
    }finally{Pop-Location}
}finally{$env:ASPAN_RUST_LIB=$previousLib;Pop-Location;$SpanMutex.ReleaseMutex();$SpanMutex.Dispose()}
