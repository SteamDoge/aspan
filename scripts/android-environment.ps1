# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 ASpan contributors.
# The shared NDK executables inherit Low mandatory integrity from the existing
# AQ toolchain. Give only ASpan's disposable Android outputs a matching label.
# Do not relabel source files, the SDK, Windows outputs, or delivery directories.
function Initialize-SpanAndroidOutput {
    param([Parameter(Mandatory=$true)][string]$Path)
    $full=[IO.Path]::GetFullPath($Path)
    $root=[IO.Path]::GetFullPath($script:SpanRoot).TrimEnd('\')
    $allowed=@('target\android','apps\aspan\build\app','apps\aspan\build\jni','apps\aspan\build\jni_flutter','apps\aspan\build\file_selector_android','apps\aspan\build\path_provider_android','apps\aspan\build\integration_test','apps\aspan\android\.gradle')
    if(-not($allowed | Where-Object {$full -ieq (Join-Path $root $_)})) {throw "Not an approved ASpan Android output directory: $full"}
    $check=$full
    while($check -ine $root) {
        if(Test-Path -LiteralPath $check) {
            if((Get-Item -LiteralPath $check -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Output path contains a reparse point: $check"}
        }
        $check=Split-Path -Parent $check
        if(-not $check){throw 'Output path escaped the workspace'}
    }
    New-Item -ItemType Directory -Path $full -Force | Out-Null
    # Only label this directory. Never traverse existing children or junctions.
    # Fresh generated objects inherit the label; shared SDK ACLs remain untouched.
    $result=& icacls $full /setintegritylevel '(OI)(CI)L' /L /Q 2>&1
    if($LASTEXITCODE -ne 0){throw "Could not prepare Android output integrity: $result"}
    return $full
}
