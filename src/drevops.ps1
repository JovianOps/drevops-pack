#!/usr/bin/env pwsh
#
# Host-side wrapper for PowerShell: runs the drevops-pack image.
#
# Usage:
#   .\drevops.ps1 list
#   .\drevops.ps1 vortex-tooling ci
#
# Env:
#   $env:DREVOPS_IMAGE           image to use (default: drevops-pack:latest)
#   $env:DREVOPS_DOCKER=1        also mount the Docker socket
#   $env:DREVOPS_ENV_PASSTHROUGH space-separated env var names to forward
#
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Args
)

$ErrorActionPreference = 'Stop'

$Image = if ($env:DREVOPS_IMAGE) { $env:DREVOPS_IMAGE } else { 'drevops-pack:latest' }

# Find docker.exe
$Docker = (Get-Command docker -ErrorAction SilentlyContinue) | Select-Object -First 1
if ($Docker) { $Docker = $Docker.Source }
if (-not $Docker) {
    Write-Error 'drevops: docker is required but was not found in PATH'
    exit 127
}

$VolArg = "$(Get-Location):/work"

$DockerArgs = @(
    'run', '--rm', '--interactive',
    "--volume=$VolArg", '--workdir=/work',
    '--env=HOME=/tmp'
)

# Only set --user on Unix Linux (Docker Desktop on Windows/Mac handles ownership)
$IsWindows = [System.Environment]::OSVersion.Platform -eq 'Win32NT'
$IsMac = (Test-Path /usr/bin/uname) -and ((uname -s) -match 'Darwin')
if (-not $IsWindows -and -not $IsMac) {
    $DockerArgs += "--user=$(id -u):$(id -g)"
}

# TTY if stdin AND stdout are interactive
if ($Host.Name -ne 'ConsoleHost') {
    # Non-interactive (e.g. redirected output) — skip TTY.
} elseif ($IsWindows) {
    # Windows: TTY detection is unreliable; skip --tty.
} else {
    $DockerArgs += '--tty'
}

if ($env:DREVOPS_DOCKER -eq '1') {
    if (Test-Path '/var/run/docker.sock') {
        $DockerArgs += '--volume=/var/run/docker.sock:/var/run/docker.sock'
    } else {
        Write-Error 'drevops: DREVOPS_DOCKER=1 but /var/run/docker.sock does not exist'
        exit 1
    }
}

if ($env:DREVOPS_ENV_PASSTHROUGH) {
    foreach ($var in $env:DREVOPS_ENV_PASSTHROUGH -split ' ') {
        if ($var) {
            $DockerArgs += "--env=$var"
        }
    }
}

& $Docker @DockerArgs -- $Image @Args
