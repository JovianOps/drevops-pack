#!/usr/bin/env pwsh
#
# Tests for the PowerShell host wrapper. Mocks docker.exe to verify
# that the correct arguments are constructed - no real Docker needed.
#
param([switch]$SkipDockerDependent)

$ErrorActionPreference = 'Stop'
$script:PASS = 0
$script:FAIL = 0

function Assert-True([string]$Label, [bool]$Cond) {
    if ($Cond) {
        $script:PASS++
        Write-Output "ok  $Label"
    } else {
        $script:FAIL++
        Write-Output "FAIL $Label"
    }
}

function Assert-Contains([string]$Label, [string]$Needle, [string]$Haystack) {
    if ($Haystack.IndexOf($Needle) -ge 0) {
        $script:PASS++
        Write-Output "ok  $Label"
    } else {
        $script:FAIL++
        Write-Output "FAIL $Label - expected to find: $Needle"
        Write-Output "     in: $Haystack"
    }
}

$Root = Split-Path $PSScriptRoot -Parent
$Wrapper = Join-Path $Root 'src/drevops.ps1'

# Create a fake docker that echoes its args
$FakeBin = Join-Path $env:TEMP ("drevops-test-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $FakeBin -Force | Out-Null

$FakeDockerExe = Join-Path $FakeBin 'docker.bat'
@'
@echo off
echo DOCKER
:loop
if "%~1"=="" goto end
echo T:%~1
shift
goto loop
:end
'@ | Set-Content $FakeDockerExe

$env:PATH = "$FakeBin;$env:PATH"

# Test 1: wrapper invokes docker with run --rm
$output = & $Wrapper list 2>&1
Assert-True "wrapper invokes docker" (($output -match 'DOCKER').Count -gt 0)
Assert-Contains "wrapper uses run --rm" '--rm' ($output -join "`n")
Assert-Contains "wrapper mounts PWD as volume" '/work' ($output -join "`n")
Assert-Contains "wrapper ends with -- before image" '--' ($output -join "`n")

# Test 2: args forwarded after image
$output = & $Wrapper vortex-tooling ci --flag 2>&1
Assert-Contains "wrapper forwards args" 'vortex-tooling' ($output -join "`n")
Assert-Contains "wrapper forwards ci" 'ci' ($output -join "`n")
Assert-Contains "wrapper forwards --flag" '--flag' ($output -join "`n")

# Test 3: DREVOPS_IMAGE respected
$save = $env:DREVOPS_IMAGE
$env:DREVOPS_IMAGE = 'myimage:custom'
$output = & $Wrapper list 2>&1
$env:DREVOPS_IMAGE = $save
Assert-Contains "wrapper uses DREVOPS_IMAGE" 'myimage:custom' ($output -join "`n")

# Test 4: missing docker errors cleanly
$env:PATH = ($env:PATH -split ';' | Where-Object { $_ -ne $FakeBin }) -join ';'
try {
    $output = & $Wrapper list 2>&1
    $exitCode = $LASTEXITCODE
    Assert-True "missing docker exits 127" ($exitCode -eq 127)
    Assert-Contains "missing docker mentions docker" 'docker' ($output -join "`n")
} catch {
    Assert-True "missing docker throws" $true
}
$env:PATH = "$FakeBin;$env:PATH"

# Test 5: DREVOPS_ENV_PASSTHROUGH forwards env
$env:DREVOPS_test_var = 'myvalue'
$env:DREVOPS_ENV_PASSTHROUGH = 'DREVOPS_test_var'
try {
    $output = & $Wrapper list 2>&1
    Assert-Contains "env passthrough forwards var" 'DREVOPS_test_var' ($output -join "`n")
} finally {
    $env:DREVOPS_ENV_PASSTHROUGH = ''
    $env:DREVOPS_test_var = ''
}

# Test 6: works with no args (leaves CMD to image)
$output = & $Wrapper 2>&1
Assert-True "no args still invokes docker" (($output -match 'DOCKER').Count -gt 0)
Assert-Contains "no args has -- before image" '--' ($output -join "`n")

# Cleanup
Remove-Item -Recurse -Force $FakeBin -ErrorAction SilentlyContinue

Write-Output ""
Write-Output "$PASS passed, $FAIL failed"
if ($FAIL -eq 0) { exit 0 } else { exit 1 }
