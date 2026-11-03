# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 ASpan contributors.
#requires -Version 7.0
param([string]$Flutter='')
. (Join-Path $PSScriptRoot 'environment.ps1') -Flutter $Flutter
Push-Location $SpanRoot
try{
    Invoke-Span cargo @('build','-p','aspan-runtime','--locked')
    Initialize-SpanPlugins
    Push-Location $SpanClient
    try{Invoke-Span $SpanFlutter @('run','-d','windows')}finally{Pop-Location}
}finally{Pop-Location;$SpanMutex.ReleaseMutex();$SpanMutex.Dispose()}
