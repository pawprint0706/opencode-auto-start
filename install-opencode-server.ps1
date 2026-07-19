# Run directly in PowerShell, or through install-opencode-server.bat.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$taskName = 'OpenCode Server'
$configDir = Join-Path $env:LOCALAPPDATA 'OpenCode'
$passwordPath = Join-Path $configDir 'server-password.dpapi'
$binDir = Join-Path $env:LOCALAPPDATA 'OpenCode\bin'
$wrapperPath = Join-Path $binDir 'opencode-server.ps1'
$logDir = Join-Path $env:LOCALAPPDATA 'OpenCode\Logs'

function Invoke-Schtasks {
    param([string[]]$Arguments)

    & schtasks.exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "schtasks.exe failed with exit code $LASTEXITCODE."
    }
}

function Remove-Service {
    $null = & schtasks.exe /Delete /TN $taskName /F 2>$null
    Remove-Item -Force -ErrorAction SilentlyContinue $wrapperPath, $passwordPath
    Write-Host 'OpenCode server automatic startup has been removed.'
}

function Install-Service {
    $opencode = Get-Command opencode -ErrorAction SilentlyContinue
    if ($null -eq $opencode) {
        Write-Host 'OpenCode CLI was not found. Install OpenCode first:'
        Write-Host '  npm: npm install -g opencode-ai'
        return
    }

    $portText = Read-Host 'Server port [4096]'
    $port = if ([string]::IsNullOrWhiteSpace($portText)) { 4096 } else { 0 }
    if ($port -eq 0 -and -not [int]::TryParse($portText, [ref]$port)) {
        Write-Host 'The port must be a number from 1 through 65535.'
        return
    }
    if ($port -lt 1 -or $port -gt 65535) {
        Write-Host 'The port must be a number from 1 through 65535.'
        return
    }

    if (Test-Path $passwordPath) {
        $keepPassword = Read-Host 'Keep the existing server password? [Y/n]'
    }
    if (-not (Test-Path $passwordPath) -or $keepPassword -notmatch '^(?i:y|yes)?$') {
        $password = Read-Host 'OpenCode server password' -AsSecureString
        if ($password.Length -eq 0) {
            Write-Host 'The password cannot be empty.'
            return
        }
        New-Item -ItemType Directory -Force $configDir | Out-Null
        $password | ConvertFrom-SecureString | Set-Content -NoNewline $passwordPath
    }

    New-Item -ItemType Directory -Force $binDir, $logDir | Out-Null
    $opencodePath = $opencode.Source.Replace("'", "''")
    $escapedPasswordPath = $passwordPath.Replace("'", "''")
    $escapedOutLog = (Join-Path $logDir 'opencode-server.out.log').Replace("'", "''")
    $escapedErrLog = (Join-Path $logDir 'opencode-server.err.log').Replace("'", "''")
    $wrapper = @"
`$ErrorActionPreference = 'Stop'
`$passwordFile = '$escapedPasswordPath'
`$outLog = '$escapedOutLog'
`$errLog = '$escapedErrLog'

try {
    if (-not (Test-Path -LiteralPath `$passwordFile)) {
        throw 'OpenCode server password file is missing.'
    }
    `$securePassword = ConvertTo-SecureString (Get-Content -LiteralPath `$passwordFile -Raw)
    `$passwordBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(`$securePassword)
    try {
        Set-Location -LiteralPath `$HOME
        `$env:OPENCODE_SERVER_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(`$passwordBstr)
        & '$opencodePath' serve --hostname 0.0.0.0 --port $port 1>> `$outLog 2>> `$errLog
    }
    finally {
        if (`$passwordBstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR(`$passwordBstr)
        }
        Remove-Item Env:OPENCODE_SERVER_PASSWORD -ErrorAction SilentlyContinue
    }
}
catch {
    `$_.Exception.Message | Add-Content -LiteralPath `$errLog
    exit 1
}
"@
    Set-Content -NoNewline $wrapperPath $wrapper

    $taskCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$wrapperPath`""
    $null = & schtasks.exe /Delete /TN $taskName /F 2>$null
    Invoke-Schtasks @('/Create', '/TN', $taskName, '/TR', $taskCommand, '/SC', 'ONLOGON', '/RL', 'LIMITED', '/F')
    Invoke-Schtasks @('/Run', '/TN', $taskName)

    Write-Host 'OpenCode server has been installed and started.'
    Write-Host "LAN address: http://$env:COMPUTERNAME`:$port"
    Write-Host "Status: schtasks /Query /TN `"$taskName`" /V /FO LIST"
}

Clear-Host
Write-Host 'OpenCode Server Automatic Startup'
Write-Host '1) Install or reinstall'
Write-Host '2) Remove'
$action = Read-Host 'Select [1/2]'

switch ($action) {
    '1' { Install-Service }
    '2' {
        $confirm = Read-Host 'Delete the startup task, wrapper, and saved password? [y/N]'
        if ($confirm -match '^(?i:y|yes)$') {
            Remove-Service
        }
        else {
            Write-Host 'Cancelled.'
        }
    }
    default { Write-Host 'Select 1 or 2.' }
}
