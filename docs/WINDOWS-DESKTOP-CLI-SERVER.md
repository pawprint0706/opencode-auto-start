# Windows OpenCode Desktop에 CLI Server 등록

Windows에서 자동 시작 중인 OpenCode CLI 서버를 OpenCode Desktop의 추가 서버로 등록하는 방법입니다. Desktop의 기본 서버는 기존 값인 `sidecar`로 유지하며, `CLI Server`라는 이름의 연결만 추가합니다.

## 전제 조건

- `install-opencode-server.bat`으로 CLI 서버가 설치되어 있어야 합니다.
- CLI 서버가 `http://127.0.0.1:4096`에서 실행 중이어야 합니다.
- `%LOCALAPPDATA%\OpenCode\server-password.dpapi`가 존재해야 합니다.
- OpenCode Desktop을 완전히 종료한 상태에서 진행해야 합니다.

Desktop이 실행 중이면 종료 과정에서 설정 파일을 다시 저장하여 수동 변경을 덮어쓸 수 있습니다. 작업 관리자에 `%LOCALAPPDATA%\Programs\@opencode-aidesktop\OpenCode.exe` 프로세스가 남아 있지 않은지 확인하세요.

## 저장 위치

OpenCode Desktop은 서버 설정을 다음 파일에 저장합니다.

- Desktop 일반 설정: `%APPDATA%\ai.opencode.desktop\opencode.settings`
- 서버 연결 목록: `%APPDATA%\ai.opencode.desktop\opencode.global.dat`
- CLI 서버 비밀번호: `%LOCALAPPDATA%\OpenCode\server-password.dpapi`

`opencode.settings`의 `defaultServerUrl`은 수정하지 않습니다. 기본 Desktop 내장 서버를 사용하는 경우 이 값은 일반적으로 `sidecar`입니다.

`opencode.global.dat`은 JSON 파일이지만 `server` 속성의 값이 다시 JSON 문자열로 저장되는 중첩 구조입니다. 직접 편집하기보다 아래 PowerShell 스크립트를 사용하는 것이 안전합니다.

## 등록

OpenCode Desktop을 완전히 종료한 뒤 Windows PowerShell 5.1에서 다음 스크립트를 실행합니다.

```powershell
$ErrorActionPreference = 'Stop'

$serverUrl = 'http://127.0.0.1:4096'
$serverName = 'CLI Server'
$desktopDir = Join-Path $env:APPDATA 'ai.opencode.desktop'
$desktopPath = Join-Path $env:LOCALAPPDATA 'Programs\@opencode-aidesktop\OpenCode.exe'
$globalPath = Join-Path $desktopDir 'opencode.global.dat'
$passwordPath = Join-Path $env:LOCALAPPDATA 'OpenCode\server-password.dpapi'

$desktopProcesses = Get-Process -Name OpenCode -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -eq $desktopPath
}
if ($desktopProcesses) {
    throw 'OpenCode Desktop을 완전히 종료한 뒤 다시 실행하세요.'
}
foreach ($path in @($globalPath, $passwordPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "필요한 파일이 없습니다: $path"
    }
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $env:TEMP "opencode-desktop-backup-$timestamp"
New-Item -ItemType Directory -Path $backupDir | Out-Null
Copy-Item -LiteralPath $globalPath -Destination $backupDir

$securePassword = ConvertTo-SecureString ([IO.File]::ReadAllText($passwordPath))
$passwordBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)

try {
    $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordBstr)
    $token = [Convert]::ToBase64String(
        [Text.Encoding]::UTF8.GetBytes("opencode:$password")
    )
    $health = Invoke-RestMethod `
        -Uri "$serverUrl/global/health" `
        -Headers @{ Authorization = "Basic $token" } `
        -TimeoutSec 5
    if (-not $health.healthy) {
        throw 'CLI 서버 상태 확인에 실패했습니다.'
    }

    $global = [IO.File]::ReadAllText($globalPath, [Text.Encoding]::UTF8) |
        ConvertFrom-Json

    if ($global.PSObject.Properties.Name -contains 'server') {
        $serverState = $global.server | ConvertFrom-Json
    }
    else {
        $serverState = [pscustomobject]@{
            list = @()
            projects = [pscustomobject]@{}
            lastProject = [pscustomobject]@{}
            recentlyClosed = [pscustomobject]@{}
        }
    }

    $connection = [pscustomobject]@{
        type = 'http'
        displayName = $serverName
        http = [pscustomobject]@{
            url = $serverUrl
            username = 'opencode'
            password = $password
        }
    }

    $remaining = @($serverState.list | Where-Object {
        $url = if ($_ -is [string]) {
            $_
        }
        elseif ($_.http) {
            $_.http.url
        }
        else {
            $_.url
        }
        $url -ne $serverUrl
    })
    $serverState.list = @($connection) + $remaining
    $serverJson = $serverState | ConvertTo-Json -Depth 20 -Compress

    if ($global.PSObject.Properties.Name -contains 'server') {
        $global.server = $serverJson
    }
    else {
        $global | Add-Member -NotePropertyName server -NotePropertyValue $serverJson
    }

    $utf8 = New-Object Text.UTF8Encoding($false)
    $tempPath = "$globalPath.tmp"
    [IO.File]::WriteAllText(
        $tempPath,
        ($global | ConvertTo-Json -Depth 20),
        $utf8
    )
    [IO.File]::Replace($tempPath, $globalPath, $null)

    Write-Host "등록 완료: $serverName ($serverUrl)"
    Write-Host "서버 버전: $($health.version)"
    Write-Host "백업 위치: $backupDir"
}
finally {
    $password = $null
    $token = $null
    if ($passwordBstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordBstr)
    }
}
```

스크립트는 같은 URL의 연결이 있으면 중복 추가하지 않고 `CLI Server` 정보로 교체합니다. `opencode.settings`를 수정하지 않으므로 기존 기본 서버 값은 유지됩니다.

## 확인

1. OpenCode Desktop을 다시 실행합니다.
2. 서버 선택 또는 서버 설정 화면을 엽니다.
3. 목록에 `CLI Server`가 표시되는지 확인합니다.
4. `CLI Server`를 선택하고 상태 표시가 정상인지 확인합니다.

앱 시작 시 기본 연결은 기존 `sidecar`이며, 필요할 때 `CLI Server`를 선택해 사용할 수 있습니다.

## 보안 주의사항

OpenCode Desktop의 공식 연결 저장 형식은 Basic Auth 비밀번호를 `opencode.global.dat`에 평문으로 저장합니다. 이 파일과 백업 파일은 외부에 공유하거나 저장소에 커밋하지 마세요. Windows 사용자 프로필에 접근할 수 있는 계정만 파일을 읽을 수 있도록 권한을 유지하세요.

Desktop 업데이트로 내부 저장 형식이 변경될 수 있습니다. 등록 후 앱이 설정을 읽지 못한다면 백업 파일로 복원하고 최신 OpenCode Desktop의 저장 형식을 다시 확인하세요.
