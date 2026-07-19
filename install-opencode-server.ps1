# Run directly in PowerShell, or through install-opencode-server.bat.

[CmdletBinding()]
param(
    [ValidateSet('Interactive', 'RegisterTask', 'RemoveTask')]
    [string]$Mode = 'Interactive',
    [string]$TaskOwnerSid,
    [string]$TaskActionPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$taskName = 'OpenCode Server'
$configDir = Join-Path $env:LOCALAPPDATA 'OpenCode'
$passwordPath = Join-Path $configDir 'server-password.dpapi'
$binDir = Join-Path $env:LOCALAPPDATA 'OpenCode\bin'
$wrapperPath = Join-Path $binDir 'opencode-server.ps1'
$logDir = Join-Path $env:LOCALAPPDATA 'OpenCode\Logs'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-TaskOwner {
    param(
        [object]$Task,
        [string]$OwnerSid
    )

    try {
        $principal = New-Object Security.Principal.NTAccount($Task.Principal.UserId)
        $principalSid = $principal.Translate([Security.Principal.SecurityIdentifier]).Value
    }
    catch {
        $principalSid = $Task.Principal.UserId
    }
    return $principalSid -eq $OwnerSid
}

function Stop-ServerTask {
    param([string]$OwnerSid)

    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($null -eq $task) {
        return
    }
    if (-not (Test-TaskOwner -Task $task -OwnerSid $OwnerSid)) {
        throw [InvalidOperationException]::new("The scheduled task '$taskName' belongs to another user.")
    }

    if ($task.State -eq 'Running') {
        Stop-ScheduledTask -TaskName $taskName
        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            Start-Sleep -Milliseconds 250
            $task = Get-ScheduledTask -TaskName $taskName
            if ($task.State -ne 'Running') {
                return
            }
        }
        throw "The scheduled task '$taskName' did not stop."
    }
}

function Register-ServerTask {
    param(
        [string]$OwnerSid,
        [string]$ActionPath
    )

    Import-Module ScheduledTasks
    Stop-ServerTask -OwnerSid $OwnerSid

    $powerShellPath = Join-Path $PSHOME 'powershell.exe'
    $action = New-ScheduledTaskAction -Execute $powerShellPath -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ActionPath`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $OwnerSid
    $principal = New-ScheduledTaskPrincipal -UserId $OwnerSid -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -MultipleInstances IgnoreNew `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries
    $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings

    Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
    Start-Sleep -Seconds 2

    $registeredTask = Get-ScheduledTask -TaskName $taskName
    if ($registeredTask.State -ne 'Running') {
        throw [InvalidOperationException]::new('The scheduled task started but the OpenCode server exited. Check the error log.')
    }
}

function Remove-ServerTask {
    param([string]$OwnerSid)

    Import-Module ScheduledTasks
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($null -eq $task) {
        return
    }
    if (-not (Test-TaskOwner -Task $task -OwnerSid $OwnerSid)) {
        throw [InvalidOperationException]::new("The scheduled task '$taskName' belongs to another user.")
    }

    Stop-ServerTask -OwnerSid $OwnerSid
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

function Invoke-ElevatedTaskOperation {
    param(
        [ValidateSet('RegisterTask', 'RemoveTask')]
        [string]$Operation,
        [string]$OwnerSid,
        [string]$ActionPath
    )

    $powerShellPath = Join-Path $PSHOME 'powershell.exe'
    $argumentList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Mode $Operation -TaskOwnerSid `"$OwnerSid`""
    if ($Operation -eq 'RegisterTask') {
        $argumentList += " -TaskActionPath `"$ActionPath`""
    }

    try {
        $process = Start-Process -FilePath $powerShellPath -ArgumentList $argumentList -Verb RunAs -Wait -PassThru -ErrorAction Stop
    }
    catch {
        throw "Administrator approval was cancelled or failed: $($_.Exception.Message)"
    }
    if ($process.ExitCode -ne 0) {
        throw "The elevated task operation failed with exit code $($process.ExitCode)."
    }
}

function Invoke-TaskOperation {
    param(
        [ValidateSet('RegisterTask', 'RemoveTask')]
        [string]$Operation,
        [string]$OwnerSid,
        [string]$ActionPath
    )

    try {
        if ($Operation -eq 'RegisterTask') {
            Register-ServerTask -OwnerSid $OwnerSid -ActionPath $ActionPath
        }
        else {
            Remove-ServerTask -OwnerSid $OwnerSid
        }
    }
    catch {
        if ($_.Exception -is [InvalidOperationException]) {
            throw
        }
        if (Test-Administrator) {
            throw
        }
        Write-Host 'Administrator approval is required to update the scheduled task.'
        Invoke-ElevatedTaskOperation -Operation $Operation -OwnerSid $OwnerSid -ActionPath $ActionPath
    }
}

function Install-Service {
    $opencode = Get-Command opencode -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $opencode) {
        Write-Host 'OpenCode CLI was not found. Install OpenCode first:'
        Write-Host '  npm: npm install -g opencode-ai'
        return $false
    }

    $portText = Read-Host 'Server port [4096]'
    $port = if ([string]::IsNullOrWhiteSpace($portText)) { 4096 } else { 0 }
    if ($port -eq 0 -and -not [int]::TryParse($portText, [ref]$port)) {
        Write-Host 'The port must be a number from 1 through 65535.'
        return $false
    }
    if ($port -lt 1 -or $port -gt 65535) {
        Write-Host 'The port must be a number from 1 through 65535.'
        return $false
    }

    $keepPassword = ''
    if (Test-Path -LiteralPath $passwordPath) {
        $keepPassword = Read-Host 'Keep the existing server password? [Y/n]'
    }
    if (-not (Test-Path -LiteralPath $passwordPath) -or $keepPassword -notmatch '^(?i:y|yes)?$') {
        $password = Read-Host 'OpenCode server password' -AsSecureString
        if ($password.Length -eq 0) {
            Write-Host 'The password cannot be empty.'
            return $false
        }
        New-Item -ItemType Directory -Force $configDir | Out-Null
        [System.IO.File]::WriteAllText(
            $passwordPath,
            ($password | ConvertFrom-SecureString),
            [System.Text.Encoding]::ASCII
        )
    }

    New-Item -ItemType Directory -Force $binDir, $logDir | Out-Null
    $opencodePath = $opencode.Path.Replace("'", "''")
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
        if (`$LASTEXITCODE -ne 0) {
            throw "OpenCode exited with code `$LASTEXITCODE."
        }
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
    [System.IO.File]::WriteAllText($wrapperPath, $wrapper, [System.Text.Encoding]::Unicode)

    $ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    Invoke-TaskOperation -Operation RegisterTask -OwnerSid $ownerSid -ActionPath $wrapperPath

    Write-Host 'OpenCode server has been installed and started.'
    Write-Host "LAN address: http://$env:COMPUTERNAME`:$port"
    Write-Host "Logs: $logDir"
    return $true
}

function Remove-Service {
    $ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    Invoke-TaskOperation -Operation RemoveTask -OwnerSid $ownerSid -ActionPath ''
    Remove-Item -Force -ErrorAction SilentlyContinue $wrapperPath, $passwordPath
    Write-Host 'OpenCode server automatic startup has been removed.'
    return $true
}

try {
    if ($Mode -eq 'RegisterTask') {
        if ([string]::IsNullOrWhiteSpace($TaskOwnerSid) -or [string]::IsNullOrWhiteSpace($TaskActionPath)) {
            throw 'Task owner SID and action path are required.'
        }
        Register-ServerTask -OwnerSid $TaskOwnerSid -ActionPath $TaskActionPath
        exit 0
    }
    if ($Mode -eq 'RemoveTask') {
        if ([string]::IsNullOrWhiteSpace($TaskOwnerSid)) {
            throw 'Task owner SID is required.'
        }
        Remove-ServerTask -OwnerSid $TaskOwnerSid
        exit 0
    }

    Clear-Host
    Write-Host 'OpenCode Server Automatic Startup'
    Write-Host '1) Install or reinstall'
    Write-Host '2) Remove'
    $action = Read-Host 'Select [1/2]'

    $succeeded = switch ($action) {
        '1' { Install-Service }
        '2' {
            $confirm = Read-Host 'Delete the startup task, wrapper, and saved password? [y/N]'
            if ($confirm -match '^(?i:y|yes)$') {
                Remove-Service
            }
            else {
                Write-Host 'Cancelled.'
                $true
            }
        }
        default {
            Write-Host 'Select 1 or 2.'
            $false
        }
    }
    if (-not $succeeded) {
        exit 1
    }
}
catch {
    [Console]::Error.WriteLine("Error: $($_.Exception.Message)")
    exit 1
}
