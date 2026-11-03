# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 ASpan contributors.
#requires -Version 7.0
param([string]$Flutter='')
. (Join-Path $PSScriptRoot 'environment.ps1') -Flutter $Flutter
$previousOutput=$env:ASPAN_TEST_OUTPUT
Push-Location $SpanRoot
try{
    Invoke-Span cargo @('build','-p','aspan-runtime','--locked')
    Initialize-SpanPlugins
    $env:ASPAN_TEST_OUTPUT=Join-Path $SpanRoot 'output/native'
    Push-Location $SpanClient
    try{Invoke-Span $SpanFlutter @('test','integration_test/app_test.dart','-d','windows')}finally{Pop-Location}
}finally{$env:ASPAN_TEST_OUTPUT=$previousOutput;Pop-Location;$SpanMutex.ReleaseMutex();$SpanMutex.Dispose()}
