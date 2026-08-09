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
$contextMenuName = 'OpenCode'
# Built from code points so the label stays correct even if the script encoding is misdetected.
$contextMenuLabel = -join @('OpenCode', [char]0xC5D0, [char]0xC11C, ' ', [char]0xC5F4, [char]0xAE30)
$configDir = Join-Path $env:LOCALAPPDATA 'OpenCode'
$passwordPath = Join-Path $configDir 'server-password.dpapi'
$iconSourcePath = Join-Path $PSScriptRoot 'icon.ico'
$contextMenuIconPath = Join-Path $configDir 'icon.ico'
$binDir = Join-Path $env:LOCALAPPDATA 'OpenCode\bin'
$wrapperPath = Join-Path $binDir 'opencode-server.ps1'
$launcherPath = Join-Path $binDir 'opencode-server.vbs'
$attachPath = Join-Path $binDir 'opencode-attach.ps1'
$updateScriptPath = Join-Path $binDir 'opencode-update.ps1'
$logDir = Join-Path $env:LOCALAPPDATA 'OpenCode\Logs'
$settingsPath = Join-Path $configDir 'server-settings.json'
$updateLogPath = Join-Path $logDir 'opencode-update.log'
$globalConfigDir = Join-Path $HOME '.config\opencode'
$globalConfigPath = Join-Path $globalConfigDir 'opencode.json'
$destructiveCommandPatterns = @(
    'rm -rf *',
    'rm -fr *',
    'rm *-?*f*',
    'rm *-f*?*',
    'sudo rm *-?*f*',
    'sudo rm *-f*?*',
    'find *-delete*',
    'sudo find *-delete*',
    '?emove-?tem *-?ecursive*',
    'rm *-?ecursive*',
    'rm *--recursive*',
    'sudo rm *--recursive*',
    'del */?*',
    'erase */?*',
    'rd */?*',
    'rmdir */?*',
    'git clean *-f*d*',
    'git clean *-d*f*',
    'diskutil eraseDisk *',
    'diskutil eraseVolume *',
    'diskutil zeroDisk *',
    'diskutil secureErase *',
    'diskutil partitionDisk *',
    'sudo diskutil eraseDisk *',
    'sudo diskutil eraseVolume *',
    'sudo diskutil zeroDisk *',
    'sudo diskutil secureErase *',
    'sudo diskutil partitionDisk *',
    'mkfs *',
    'sudo mkfs *',
    'newfs *',
    'sudo newfs *',
    'dd *of=/dev/*',
    'sudo dd *of=/dev/*',
    '?lear-?isk *',
    '?ormat-?olume *',
    '?nitialize-?isk *',
    'format *',
    'diskpart *'
)
$contextMenuRoots = @(
    'HKCU:\Software\Classes\Directory\Background\shell',
    'HKCU:\Software\Classes\Directory\shell',
    'HKCU:\Software\Classes\Drive\shell'
)

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

function Stop-ServerProcesses {
    $wrapperPattern = '(?i)(?:^|\s)-File\s+(?:"{0}"|{0})(?:\s|$)' -f [regex]::Escape($wrapperPath)
    $processes = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" | Where-Object {
        $_.CommandLine -match $wrapperPattern
    }

    $taskkillPath = Join-Path $env:SystemRoot 'System32\taskkill.exe'
    foreach ($process in $processes) {
        & $taskkillPath /PID $process.ProcessId /T /F 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -and (Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue)) {
            throw "The OpenCode server process $($process.ProcessId) did not stop."
        }
    }
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
                break
            }
        }
        if ($task.State -eq 'Running') {
            throw "The scheduled task '$taskName' did not stop."
        }
    }

    # Stopping the WScript task does not terminate the PowerShell/OpenCode child processes.
    Stop-ServerProcesses
}

function Register-ServerTask {
    param(
        [string]$OwnerSid,
        [string]$ActionPath
    )

    Import-Module ScheduledTasks
    Stop-ServerTask -OwnerSid $OwnerSid

    # A GUI script host prevents Windows 11 terminal delegation from creating a visible window.
    $wscriptPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $action = New-ScheduledTaskAction -Execute $wscriptPath -Argument "//B //NoLogo `"$ActionPath`""
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

function Register-ContextMenu {
    param(
        [string]$AttachScriptPath,
        [string]$IconPath
    )

    $powerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $useWindowsTerminal = $null -ne (Get-Command wt.exe -ErrorAction SilentlyContinue)

    $entries = @(
        @{ Root = 'HKCU:\Software\Classes\Directory\Background\shell'; Target = '%V' },
        @{ Root = 'HKCU:\Software\Classes\Directory\shell'; Target = '%1' },
        @{ Root = 'HKCU:\Software\Classes\Drive\shell'; Target = '%1' }
    )

    foreach ($entry in $entries) {
        $menuKey = Join-Path $entry.Root $contextMenuName
        $commandKey = Join-Path $menuKey 'command'
        New-Item -Path $menuKey -Force | Out-Null
        Set-ItemProperty -LiteralPath $menuKey -Name '(default)' -Value $contextMenuLabel
        if (-not [string]::IsNullOrWhiteSpace($IconPath)) {
            Set-ItemProperty -LiteralPath $menuKey -Name 'Icon' -Value $IconPath
        }

        if ($useWindowsTerminal) {
            $command = 'wt.exe -d "{0}" "{1}" -NoProfile -ExecutionPolicy Bypass -File "{2}" -Dir "{0}"' -f `
                $entry.Target, $powerShellPath, $AttachScriptPath
        }
        else {
            $command = '"{0}" -NoExit -NoProfile -ExecutionPolicy Bypass -File "{1}" -Dir "{2}"' -f `
                $powerShellPath, $AttachScriptPath, $entry.Target
        }

        New-Item -Path $commandKey -Force | Out-Null
        Set-ItemProperty -LiteralPath $commandKey -Name '(default)' -Value $command
    }
}

function Remove-ContextMenu {
    foreach ($root in $contextMenuRoots) {
        $menuKey = Join-Path $root $contextMenuName
        if (Test-Path -LiteralPath $menuKey) {
            Remove-Item -LiteralPath $menuKey -Recurse -Force
        }
    }
}

function Get-ServerSetting {
    param([string]$Name)

    if (Test-Path -LiteralPath $settingsPath) {
        try {
            $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
            if ($settings.PSObject.Properties.Name -contains $Name) {
                return $settings.$Name
            }
        }
        catch {
        }
    }
    return $null
}

function ConvertTo-BoolSetting {
    param([object]$Value)

    if ($null -eq $Value) {
        return $false
    }
    if ($Value -is [bool]) {
        return [bool]$Value
    }
    if ($Value -is [string]) {
        $parsed = $false
        if ([bool]::TryParse($Value.Trim(), [ref]$parsed)) {
            return $parsed
        }
    }
    return [bool]$Value
}

function Get-AutoUpdateEnabled {
    $value = Get-ServerSetting -Name 'autoUpdate'
    if ($null -ne $value) {
        return (ConvertTo-BoolSetting $value)
    }
    return $true
}

function Set-ServerSetting {
    param(
        [string]$Name,
        [object]$Value
    )

    New-Item -ItemType Directory -Force $configDir | Out-Null
    $settings = [pscustomobject]@{}
    if (Test-Path -LiteralPath $settingsPath) {
        try {
            $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        }
        catch {
            $settings = [pscustomobject]@{}
        }
    }
    $settings | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    $utf8 = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json -Depth 5), $utf8)
}

function Set-AutoUpdateEnabled {
    param([bool]$Enabled)

    Set-ServerSetting -Name 'autoUpdate' -Value $Enabled
}

function ConvertFrom-JsonWithComments {
    param([string]$Json)

    $withoutComments = New-Object Text.StringBuilder
    $inString = $false
    $escaped = $false
    $lineComment = $false
    $blockComment = $false

    for ($index = 0; $index -lt $Json.Length; $index++) {
        $current = $Json[$index]
        $next = if ($index + 1 -lt $Json.Length) { $Json[$index + 1] } else { [char]0 }

        if ($lineComment) {
            if ($current -eq "`r" -or $current -eq "`n") {
                $lineComment = $false
                [void]$withoutComments.Append($current)
            }
            continue
        }
        if ($blockComment) {
            if ($current -eq '*' -and $next -eq '/') {
                $blockComment = $false
                $index++
            }
            elseif ($current -eq "`r" -or $current -eq "`n") {
                [void]$withoutComments.Append($current)
            }
            continue
        }
        if ($inString) {
            [void]$withoutComments.Append($current)
            if ($escaped) {
                $escaped = $false
            }
            elseif ($current -eq '\') {
                $escaped = $true
            }
            elseif ($current -eq '"') {
                $inString = $false
            }
            continue
        }
        if ($current -eq '"') {
            $inString = $true
            [void]$withoutComments.Append($current)
        }
        elseif ($current -eq '/' -and $next -eq '/') {
            $lineComment = $true
            $index++
        }
        elseif ($current -eq '/' -and $next -eq '*') {
            $blockComment = $true
            $index++
        }
        else {
            [void]$withoutComments.Append($current)
        }
    }

    $clean = $withoutComments.ToString()
    $withoutTrailingCommas = New-Object Text.StringBuilder
    $inString = $false
    $escaped = $false
    for ($index = 0; $index -lt $clean.Length; $index++) {
        $current = $clean[$index]
        if ($inString) {
            [void]$withoutTrailingCommas.Append($current)
            if ($escaped) {
                $escaped = $false
            }
            elseif ($current -eq '\') {
                $escaped = $true
            }
            elseif ($current -eq '"') {
                $inString = $false
            }
            continue
        }
        if ($current -eq '"') {
            $inString = $true
            [void]$withoutTrailingCommas.Append($current)
            continue
        }
        if ($current -eq ',') {
            $lookahead = $index + 1
            while ($lookahead -lt $clean.Length -and [char]::IsWhiteSpace($clean[$lookahead])) {
                $lookahead++
            }
            if ($lookahead -lt $clean.Length -and ($clean[$lookahead] -eq '}' -or $clean[$lookahead] -eq ']')) {
                continue
            }
        }
        [void]$withoutTrailingCommas.Append($current)
    }

    return ($withoutTrailingCommas.ToString() | ConvertFrom-Json)
}

function Set-GlobalSafetyPermission {
    New-Item -ItemType Directory -Force $globalConfigDir | Out-Null
    $config = [pscustomobject]@{}
    if (Test-Path -LiteralPath $globalConfigPath) {
        try {
            $config = ConvertFrom-JsonWithComments (Get-Content -LiteralPath $globalConfigPath -Raw)
        }
        catch {
            throw "The global OpenCode config could not be updated: $globalConfigPath ($($_.Exception.Message))"
        }
    }

    if ($config.PSObject.Properties.Name -notcontains '$schema') {
        $config | Add-Member -NotePropertyName '$schema' -NotePropertyValue 'https://opencode.ai/config.json'
    }
    if ($config.PSObject.Properties.Name -notcontains 'permission') {
        $config | Add-Member -NotePropertyName 'permission' -NotePropertyValue ([pscustomobject]@{})
    }
    elseif ($config.permission -is [string]) {
        $action = [string]$config.permission
        $config.permission = [pscustomobject]@{ '*' = $action }
    }

    if ($config.permission.PSObject.Properties.Name -notcontains 'bash') {
        $config.permission | Add-Member -NotePropertyName 'bash' -NotePropertyValue ([pscustomobject]@{})
    }
    elseif ($config.permission.bash -is [string]) {
        $action = [string]$config.permission.bash
        $config.permission.bash = [pscustomobject]@{ '*' = $action }
    }

    foreach ($pattern in $destructiveCommandPatterns) {
        $config.permission.bash.PSObject.Properties.Remove($pattern)
        $config.permission.bash | Add-Member -NotePropertyName $pattern -NotePropertyValue 'deny'
    }

    $utf8 = New-Object Text.UTF8Encoding($false)
    $temporaryPath = "$globalConfigPath.tmp"
    [IO.File]::WriteAllText($temporaryPath, (($config | ConvertTo-Json -Depth 100) + [Environment]::NewLine), $utf8)
    Move-Item -LiteralPath $temporaryPath -Destination $globalConfigPath -Force
}

function Get-InstalledOpencodePath {
    if (Test-Path -LiteralPath $settingsPath) {
        try {
            $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
            if ($settings.PSObject.Properties.Name -contains 'opencodePath' -and -not [string]::IsNullOrWhiteSpace($settings.opencodePath)) {
                return [string]$settings.opencodePath
            }
        }
        catch {
        }
    }
    if (Test-Path -LiteralPath $attachPath) {
        try {
            $line = Select-String -LiteralPath $attachPath -Pattern '^\$opencodePath = ''(.+)''$' | Select-Object -First 1
            if ($null -ne $line) {
                return $line.Matches[0].Groups[1].Value.Replace("''", "'")
            }
        }
        catch {
        }
    }
    return $null
}

function Install-Service {
    $opencode = Get-Command opencode -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $opencode) {
        Write-Host 'OpenCode CLI was not found. Install OpenCode first:'
        Write-Host '  npm: npm install -g opencode-ai'
        return $false
    }
    if (-not (Test-Path -LiteralPath $iconSourcePath -PathType Leaf)) {
        Write-Host "OpenCode context menu icon was not found: $iconSourcePath"
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

    $autoUpdateText = Read-Host 'Update opencode automatically at logon? [Y/n]'
    $autoUpdate = $autoUpdateText -notmatch '^(?i:n|no)$'
    Set-AutoUpdateEnabled -Enabled $autoUpdate
    $autoApproveText = Read-Host 'Enable auto-approve (all sessions)? [Y/n]'
    $autoApprove = $autoApproveText -notmatch '^(?i:n|no)$'
    Set-ServerSetting -Name 'autoApprove' -Value $autoApprove
    Set-ServerSetting -Name 'opencodePath' -Value $opencode.Path
    Set-GlobalSafetyPermission

    New-Item -ItemType Directory -Force $configDir, $binDir, $logDir | Out-Null
    Copy-Item -LiteralPath $iconSourcePath -Destination $contextMenuIconPath -Force
    $opencodePath = $opencode.Path.Replace("'", "''")
    $escapedPasswordPath = $passwordPath.Replace("'", "''")
    $escapedOutLog = (Join-Path $logDir 'opencode-server.out.log').Replace("'", "''")
    $escapedErrLog = (Join-Path $logDir 'opencode-server.err.log').Replace("'", "''")
    $escapedUpdateScript = $updateScriptPath.Replace("'", "''")
    $escapedSettingsPath = $settingsPath.Replace("'", "''")
    $autoApprovePermission = [ordered]@{ '*' = 'allow'; bash = [ordered]@{} }
    foreach ($pattern in $destructiveCommandPatterns) {
        $autoApprovePermission['bash'][$pattern] = 'deny'
    }
    $escapedAutoApprovePermission = (($autoApprovePermission | ConvertTo-Json -Compress).Replace("'", "''"))
    $wrapper = @"
`$ErrorActionPreference = 'Stop'
`$passwordFile = '$escapedPasswordPath'
`$outLog = '$escapedOutLog'
`$errLog = '$escapedErrLog'

function ConvertTo-BoolSetting {
    param([object]`$Value)

    if (`$null -eq `$Value) {
        return `$false
    }
    if (`$Value -is [bool]) {
        return [bool]`$Value
    }
    if (`$Value -is [string]) {
        `$parsed = `$false
        if ([bool]::TryParse(`$Value.Trim(), [ref]`$parsed)) {
            return `$parsed
        }
    }
    return [bool]`$Value
}

try {
    if (-not (Test-Path -LiteralPath `$passwordFile)) {
        throw 'OpenCode server password file is missing.'
    }
    `$securePassword = ConvertTo-SecureString (Get-Content -LiteralPath `$passwordFile -Raw)
    `$passwordBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(`$securePassword)
    try {
        Set-Location -LiteralPath `$HOME
        `$env:OPENCODE_SERVER_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(`$passwordBstr)
        `$settingsFile = '$escapedSettingsPath'
        try {
            if (Test-Path -LiteralPath `$settingsFile) {
                `$serverSettings = Get-Content -LiteralPath `$settingsFile -Raw | ConvertFrom-Json
                if (`$serverSettings.PSObject.Properties.Name -contains 'autoApprove' -and (ConvertTo-BoolSetting `$serverSettings.autoApprove)) {
                    `$env:OPENCODE_PERMISSION = '$escapedAutoApprovePermission'
                }
            }
        }
        catch {
        }
        `$updateScript = '$escapedUpdateScript'
        try {
            if (Test-Path -LiteralPath `$updateScript) {
                & `$updateScript -OpencodePath '$opencodePath' | Out-Null
            }
        }
        catch {
            `$_.Exception.Message | Add-Content -LiteralPath `$errLog
        }
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
        Remove-Item Env:OPENCODE_PERMISSION -ErrorAction SilentlyContinue
    }
}
catch {
    `$_.Exception.Message | Add-Content -LiteralPath `$errLog
    exit 1
}
"@
    [System.IO.File]::WriteAllText($wrapperPath, $wrapper, [System.Text.Encoding]::Unicode)

    $launcher = @'
Option Explicit

Dim command, exitCode, fileSystem, powerShellPath, scriptPath, shell
Set fileSystem = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

scriptPath = fileSystem.BuildPath(fileSystem.GetParentFolderName(WScript.ScriptFullName), "opencode-server.ps1")
powerShellPath = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
command = Chr(34) & powerShellPath & Chr(34) & " -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Chr(34) & scriptPath & Chr(34)
exitCode = shell.Run(command, 0, True)
WScript.Quit exitCode
'@
    [System.IO.File]::WriteAllText($launcherPath, $launcher, [System.Text.Encoding]::ASCII)

    $attach = @"
param(
    [Parameter(Mandatory = `$true)]
    [string]`$Dir
)

`$ErrorActionPreference = 'Stop'
`$passwordFile = '$escapedPasswordPath'
`$opencodePath = '$opencodePath'
`$serverUrl = 'http://127.0.0.1:$port'

try {
    if (-not (Test-Path -LiteralPath `$Dir)) {
        throw "Directory not found: `$Dir"
    }
    if (-not (Test-Path -LiteralPath `$passwordFile)) {
        throw 'OpenCode server password file is missing. Run the installer first.'
    }
    if (-not (Test-Path -LiteralPath `$opencodePath)) {
        throw "OpenCode CLI was not found: `$opencodePath"
    }

    `$securePassword = ConvertTo-SecureString (Get-Content -LiteralPath `$passwordFile -Raw)
    `$passwordBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR(`$securePassword)
    try {
        `$env:OPENCODE_SERVER_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(`$passwordBstr)
        Set-Location -LiteralPath `$Dir
        & `$opencodePath attach `$serverUrl --dir `$Dir
        exit `$LASTEXITCODE
    }
    finally {
        if (`$passwordBstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR(`$passwordBstr)
        }
        Remove-Item Env:OPENCODE_SERVER_PASSWORD -ErrorAction SilentlyContinue
    }
}
catch {
    [Console]::Error.WriteLine(`$_.Exception.Message)
    Read-Host 'Press Enter to close'
    exit 1
}
"@
    [System.IO.File]::WriteAllText($attachPath, $attach, [System.Text.Encoding]::Unicode)

    $escapedUpdateLog = $updateLogPath.Replace("'", "''")
    $updateScript = @'
[CmdletBinding()]
param(
    [string]$OpencodePath
)

$ErrorActionPreference = 'Stop'
$settingsPath = '__SETTINGS__'
$logPath = '__LOG__'
$updateTimeoutSeconds = 300

function Write-UpdateLog {
    param([string]$Message)

    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try {
        Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
    }
    catch {
    }
}

function ConvertTo-BoolSetting {
    param([object]$Value)

    if ($null -eq $Value) {
        return $false
    }
    if ($Value -is [bool]) {
        return [bool]$Value
    }
    if ($Value -is [string]) {
        $parsed = $false
        if ([bool]::TryParse($Value.Trim(), [ref]$parsed)) {
            return $parsed
        }
    }
    return [bool]$Value
}

function Get-UpdateCommand {
    param([string]$OpencodePath)

    $shimDir = Join-Path $HOME 'scoop\shims'
    $appsDir = Join-Path $HOME 'scoop\apps'
    $isScoopPath = $OpencodePath.StartsWith($shimDir, [StringComparison]::OrdinalIgnoreCase) -or
        $OpencodePath.StartsWith($appsDir, [StringComparison]::OrdinalIgnoreCase)

    if ($isScoopPath) {
        $scoopPs1 = Join-Path $shimDir 'scoop.ps1'
        if (Test-Path -LiteralPath $scoopPs1) {
            return @{ Tool = 'scoop'; Command = @($scoopPs1, 'update', 'opencode') }
        }
        $scoopCmd = Join-Path $shimDir 'scoop.cmd'
        if (Test-Path -LiteralPath $scoopCmd) {
            return @{ Tool = 'scoop'; Command = @($scoopCmd, 'update', 'opencode') }
        }
        $scoopCommand = Get-Command scoop -CommandType Application -ErrorAction SilentlyContinue
        if ($null -ne $scoopCommand) {
            return @{ Tool = 'scoop'; Command = @($scoopCommand.Source, 'update', 'opencode') }
        }
    }

    $npm = Get-Command npm -CommandType Application -ErrorAction SilentlyContinue
    if ($null -ne $npm) {
        try {
            $prefix = (& $npm.Source 'prefix' '-g' 2>$null | Select-Object -Last 1)
            if ($prefix -and $OpencodePath.StartsWith($prefix.Trim(), [StringComparison]::OrdinalIgnoreCase)) {
                return @{ Tool = 'npm'; Command = @($npm.Source, 'install', '-g', 'opencode-ai@latest') }
            }
        }
        catch {
        }
    }

    $pnpm = Get-Command pnpm -CommandType Application -ErrorAction SilentlyContinue
    if ($null -ne $pnpm) {
        try {
            $bin = (& $pnpm.Source 'bin' '-g' 2>$null | Select-Object -Last 1)
            if ($bin -and $OpencodePath.StartsWith($bin.Trim(), [StringComparison]::OrdinalIgnoreCase)) {
                return @{ Tool = 'pnpm'; Command = @($pnpm.Source, 'add', '-g', 'opencode-ai@latest') }
            }
        }
        catch {
        }
    }

    $yarn = Get-Command yarn -CommandType Application -ErrorAction SilentlyContinue
    if ($null -ne $yarn) {
        try {
            $bin = (& $yarn.Source 'global' 'bin' 2>$null | Select-Object -Last 1)
            if ($bin -and $OpencodePath.StartsWith($bin.Trim(), [StringComparison]::OrdinalIgnoreCase)) {
                return @{ Tool = 'yarn'; Command = @($yarn.Source, 'global', 'add', 'opencode-ai@latest') }
            }
        }
        catch {
        }
    }

    $bun = Get-Command bun -CommandType Application -ErrorAction SilentlyContinue
    if ($null -ne $bun) {
        try {
            $bin = (& $bun.Source 'pm' 'bin' '-g' 2>$null | Select-Object -Last 1)
            if ($bin -and $OpencodePath.StartsWith($bin.Trim(), [StringComparison]::OrdinalIgnoreCase)) {
                return @{ Tool = 'bun'; Command = @($bun.Source, 'add', '-g', 'opencode-ai@latest') }
            }
        }
        catch {
        }
    }

    return @{ Tool = 'self'; Command = @($OpencodePath, 'upgrade') }
}

function Invoke-UpdateCommand {
    param(
        [object]$Update,
        [int]$TimeoutSeconds
    )

    $job = Start-Job -ScriptBlock {
        param($Command)

        $args = @()
        if ($Command.Count -gt 1) {
            $args = $Command[1..($Command.Count - 1)]
        }
        & $Command[0] @args | Out-Null
        $LASTEXITCODE
    } -ArgumentList (,$Update.Command)

    if (-not (Wait-Job $job -Timeout $TimeoutSeconds)) {
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        return @{ TimedOut = $true; ExitCode = $null }
    }

    $exitCode = Receive-Job $job -Keep | Select-Object -Last 1
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    if ($null -eq $exitCode) {
        $exitCode = 0
    }
    return @{ TimedOut = $false; ExitCode = $exitCode }
}

try {
    Write-UpdateLog "Checking opencode at $OpencodePath"

    if (-not (Test-Path -LiteralPath $OpencodePath)) {
        Write-UpdateLog 'Opencode path does not exist; skipping auto-update.'
        exit 0
    }

    $enabled = $true
    if (Test-Path -LiteralPath $settingsPath) {
        try {
            $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
            if ($settings.PSObject.Properties.Name -contains 'autoUpdate') {
                $enabled = ConvertTo-BoolSetting $settings.autoUpdate
            }
        }
        catch {
            $enabled = $true
        }
    }
    if (-not $enabled) {
        Write-UpdateLog 'Auto-update is disabled in server-settings.json; skipping.'
        exit 0
    }

    $before = (& $OpencodePath --version 2>$null | Select-Object -First 1)
    $update = Get-UpdateCommand -OpencodePath $OpencodePath
    Write-UpdateLog "Updating opencode via $($update.Tool)... (version before: $before)"

    $result = Invoke-UpdateCommand -Update $update -TimeoutSeconds $updateTimeoutSeconds
    if ($result.TimedOut) {
        Write-UpdateLog "Update timed out after $updateTimeoutSeconds seconds."
        exit 0
    }

    $after = (& $OpencodePath --version 2>$null | Select-Object -First 1)
    Write-UpdateLog ("Update finished (exit code {0}). Version: {1} -> {2}" -f $result.ExitCode, $before, $after)
}
catch {
    Write-UpdateLog "Auto-update failed: $($_.Exception.Message)"
}
exit 0
'@
    $updateScript = $updateScript.Replace('__SETTINGS__', $escapedSettingsPath).Replace('__LOG__', $escapedUpdateLog)
    [System.IO.File]::WriteAllText($updateScriptPath, $updateScript, [System.Text.Encoding]::Unicode)

    $ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    Invoke-TaskOperation -Operation RegisterTask -OwnerSid $ownerSid -ActionPath $launcherPath

    Register-ContextMenu -AttachScriptPath $attachPath -IconPath $contextMenuIconPath

    Write-Host 'OpenCode server has been installed and started.'
    Write-Host "LAN address: http://$env:COMPUTERNAME`:$port"
    Write-Host "Explorer menu: $contextMenuLabel (attaches to http://127.0.0.1:$port)"
    Write-Host ('Automatic update at logon: {0}' -f $(if (Get-AutoUpdateEnabled) { 'enabled' } else { 'disabled' }))
    $autoApproveValue = Get-ServerSetting -Name 'autoApprove'
    $autoApproveEnabled = ConvertTo-BoolSetting $autoApproveValue
    Write-Host ('Auto-approve (server-wide): {0}' -f $(if ($autoApproveEnabled) { 'enabled' } else { 'disabled' }))
    Write-Host "Permanent safety rules: recursive deletion and disk erase commands are denied in $globalConfigPath"
    Write-Host "Logs: $logDir"
    return $true
}

function Remove-Service {
    $ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    Invoke-TaskOperation -Operation RemoveTask -OwnerSid $ownerSid -ActionPath ''
    Remove-ContextMenu
    Remove-Item -Force -ErrorAction SilentlyContinue `
        $wrapperPath, $launcherPath, $attachPath, $updateScriptPath, $passwordPath, $contextMenuIconPath, $settingsPath
    Write-Host 'OpenCode server automatic startup and Explorer context menu have been removed.'
    return $true
}

function Restart-Service {
    Import-Module ScheduledTasks
    $ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($null -eq $task) {
        Write-Host 'OpenCode server is not installed. Install it first.'
        return $false
    }
    if (-not (Test-TaskOwner -Task $task -OwnerSid $ownerSid)) {
        throw [InvalidOperationException]::new("The scheduled task '$taskName' belongs to another user.")
    }

    $opencodePath = Get-InstalledOpencodePath
    if (-not [string]::IsNullOrWhiteSpace($opencodePath) -and (Test-Path -LiteralPath $updateScriptPath)) {
        Write-Host 'Updating opencode...'
        & $updateScriptPath -OpencodePath $opencodePath | Out-Null
        Write-Host "Update log: $updateLogPath"
    }

    Stop-ServerTask -OwnerSid $ownerSid
    Start-ScheduledTask -TaskName $taskName
    Start-Sleep -Seconds 2

    $runningTask = Get-ScheduledTask -TaskName $taskName
    $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName
    if ($runningTask.State -ne 'Running') {
        Write-Host 'The OpenCode server is not running after restart.'
        Write-Host "Status: $($runningTask.State)"
        Write-Host ('Last task result: 0x{0:X8}' -f $taskInfo.LastTaskResult)
        Write-Host "Error log: $(Join-Path $logDir 'opencode-server.err.log')"
        return $false
    }
    Write-Host 'OpenCode server has been restarted.'
    Write-Host "Status: $($runningTask.State)"
    Write-Host "Last started: $($taskInfo.LastRunTime)"
    Write-Host "Logs: $logDir"
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

    while ($true) {
        Clear-Host
        Write-Host 'OpenCode Server Automatic Startup'
        Write-Host '1) Install or reinstall'
        Write-Host '2) Remove'
        Write-Host '3) Update and restart'
        Write-Host '4) Toggle automatic updates'
        Write-Host '5) Exit'
        $action = Read-Host 'Select [1/2/3/4/5]'

        $exitRequested = $false
        try {
            switch ($action) {
                '1' { Install-Service | Out-Null }
                '2' {
                    $confirm = Read-Host 'Delete the startup task, Explorer menu, wrapper, and saved password? [y/N]'
                    if ($confirm -match '^(?i:y|yes)$') {
                        Remove-Service | Out-Null
                    }
                    else {
                        Write-Host 'Cancelled.'
                    }
                }
                '3' { Restart-Service | Out-Null }
                '4' {
                    Set-AutoUpdateEnabled -Enabled (-not (Get-AutoUpdateEnabled))
                    Write-Host ('Automatic opencode updates at logon: {0}' -f $(if (Get-AutoUpdateEnabled) { 'enabled' } else { 'disabled' }))
                    Write-Host 'The change takes effect at the next server start.'
                }
                '5' { $exitRequested = $true }
                default {
                    Write-Host 'Select 1, 2, 3, 4 or 5.'
                }
            }
        }
        catch {
            Write-Host "Error: $($_.Exception.Message)"
        }
        if ($exitRequested) {
            break
        }
        Read-Host 'Press Enter to return to the main menu'
    }
}
catch {
    [Console]::Error.WriteLine("Error: $($_.Exception.Message)")
    exit 1
}
