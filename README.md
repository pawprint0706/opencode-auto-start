# OpenCode Server Auto Start

macOS와 Windows에서 OpenCode HTTP 서버를 로그인 시 자동으로 시작하도록 등록하는 스크립트입니다. 서버는 사용자 홈 폴더를 작업 디렉터리로 사용하며 기본 포트는 `4096`입니다.

## 요구 사항

- OpenCode CLI가 설치되어 있어야 합니다.
- macOS: `brew install anomalyco/tap/opencode` 또는 `npm install -g opencode-ai`
- Windows: `npm install -g opencode-ai`

## macOS

Finder에서 `install-opencode-server.command`를 더블클릭합니다.

1. `1`을 선택해 설치 또는 재설치를 진행합니다.
2. 포트와 서버 비밀번호를 입력합니다.
3. 로그인 시 `launchd`가 OpenCode 서버를 자동 시작합니다.

삭제하려면 같은 파일을 실행한 뒤 `2`를 선택합니다.

- 서비스: `com.anomalyco.opencode-server`
- 비밀번호: `~/.config/opencode/server-password`
- 로그: `~/Library/Logs/OpenCode/`

## Windows

Explorer에서 `install-opencode-server.bat`를 더블클릭합니다. 작업 스케줄러 변경에 관리자 권한이 필요한 경우에만 UAC 승인 창이 표시됩니다.

1. `1`을 선택해 설치 또는 재설치를 진행합니다.
2. 포트와 서버 비밀번호를 입력합니다.
3. 로그인 시 작업 스케줄러의 `OpenCode Server` 작업이 OpenCode 서버를 자동 시작합니다.

삭제하려면 같은 `.bat` 파일을 실행한 뒤 `2`를 선택합니다.

- 비밀번호: `%LOCALAPPDATA%\OpenCode\server-password.dpapi`
- 로그: `%LOCALAPPDATA%\OpenCode\Logs\`

예약 작업은 숨겨진 PowerShell 창에서 현재 사용자 로그온에만 실행되며, 배터리 사용 여부와 관계없이 계속 실행됩니다. 서버가 비정상 종료되면 작업 스케줄러가 최대 3회 다시 시작합니다.

## 접속 및 보안

서버는 LAN 접속을 위해 `0.0.0.0`에 바인딩되며 HTTP Basic Auth 비밀번호를 사용합니다. HTTPS가 아니므로 신뢰할 수 있는 네트워크에서만 사용하세요. 로컬 PC에서만 접근할 필요가 있다면 각 스크립트의 `--hostname 0.0.0.0`을 `--hostname 127.0.0.1`로 바꾸세요.

서버 문서는 `http://localhost:4096/doc`에서 확인할 수 있습니다.
