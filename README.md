# OpenCode Server Auto Start

macOS와 Windows에서 OpenCode HTTP 서버를 로그인 시 자동으로 시작하도록 등록하는 스크립트입니다. Finder 또는 탐색기의 폴더 우클릭 **OpenCode에서 열기** 메뉴도 함께 등록되어, 실행 중인 서버에 `attach`로 연결합니다. 서버는 사용자 홈 폴더를 작업 디렉터리로 사용하며 기본 포트는 `4096`입니다.

## 요구 사항

- OpenCode CLI가 설치되어 있어야 합니다.
- macOS: `brew install anomalyco/tap/opencode` 또는 `npm install -g opencode-ai`
- Windows: `npm install -g opencode-ai`

## macOS

Finder에서 `install-opencode-server.command`를 더블클릭합니다.

1. `1`을 선택해 설치 또는 재설치를 진행합니다.
2. 포트와 서버 비밀번호를 입력합니다.
3. 로그인 시 `launchd`가 OpenCode 서버를 자동 시작합니다.
4. Finder에서 폴더를 우클릭한 뒤 **빠른 동작** 또는 **서비스**의 **OpenCode에서 열기**를 선택하면 Terminal에서 실행 중인 서버(`http://127.0.0.1:<포트>`)에 `attach`로 연결됩니다.

삭제하려면 같은 파일을 실행한 뒤 `2`를, 재시작하려면 `3`을 선택합니다. 삭제 시 LaunchAgent·Finder 빠른 동작·래퍼·저장 비밀번호가 함께 제거됩니다.

- 서비스: `com.anomalyco.opencode-server`
- 비밀번호: `~/.config/opencode/server-password`
- 서버 래퍼: `~/.local/bin/opencode-server`
- attach 래퍼: `~/.local/bin/opencode-attach`
- Finder 빠른 동작: `~/Library/Services/OpenCode에서 열기.workflow`
- 로그: `~/Library/Logs/OpenCode/`

Finder 빠른 동작은 선택한 폴더에서 기본 `Terminal.app`을 열어 attach를 실행합니다. 처음 사용할 때 macOS가 Terminal 제어 권한을 요청할 수 있습니다. 메뉴가 보이지 않으면 **시스템 설정 > 일반 > 로그인 항목 및 확장 프로그램 > Finder**에서 빠른 동작이 활성화되어 있는지 확인하세요.

설치 시 현재 Terminal의 `PATH`를 서버 래퍼에 저장하므로, `npx`로 실행되는 MCP도 `launchd` 환경에서 찾을 수 있습니다. Node.js 버전 관리자 변경 등으로 실행 파일 경로가 바뀌면 설치 메뉴에서 `1`을 선택해 다시 설치하세요.

## Windows

Explorer에서 `install-opencode-server.bat`를 더블클릭합니다. 작업 스케줄러 변경에 관리자 권한이 필요한 경우에만 UAC 승인 창이 표시됩니다.

1. `1`을 선택해 설치 또는 재설치를 진행합니다.
2. 포트와 서버 비밀번호를 입력합니다.
3. 로그인 시 작업 스케줄러의 `OpenCode Server` 작업이 OpenCode 서버를 자동 시작합니다.
4. 탐색기에서 폴더/드라이브 우클릭 메뉴에 **OpenCode에서 열기**가 등록됩니다. 선택 시 실행 중인 서버(`http://127.0.0.1:<포트>`)에 `attach`로 연결됩니다.

삭제하려면 같은 `.bat` 파일을 실행한 뒤 `2`를, 재시작하려면 `3`을 선택합니다. 삭제 시 예약 작업·우클릭 메뉴·래퍼·아이콘·저장 비밀번호가 함께 제거됩니다.

- 비밀번호: `%LOCALAPPDATA%\OpenCode\server-password.dpapi`
- 우클릭 메뉴 아이콘: `%LOCALAPPDATA%\OpenCode\icon.ico`
- 서버 래퍼: `%LOCALAPPDATA%\OpenCode\bin\opencode-server.ps1`
- attach 래퍼: `%LOCALAPPDATA%\OpenCode\bin\opencode-attach.ps1`
- 로그: `%LOCALAPPDATA%\OpenCode\Logs\`

예약 작업은 Windows 10과 11에서 창이 표시되지 않도록 창 없는 런처를 통해 현재 사용자 로그온에만 실행되며, 배터리 사용 여부와 관계없이 계속 실행됩니다. 서버가 비정상 종료되면 작업 스케줄러가 최대 3회 다시 시작합니다.

우클릭 메뉴는 레지스트리에 비밀번호를 넣지 않습니다. attach 래퍼가 스케줄러와 동일한 DPAPI 비밀번호 파일을 읽어 `OPENCODE_SERVER_PASSWORD`로 전달합니다.

동작 요약:

- 백그라운드 `opencode serve`와 우클릭 `opencode attach`는 같은 서버 인스턴스(`http://127.0.0.1:<포트>`)를 공유합니다.
- 따라서 PC에서 attach로 작업한 세션을 모바일 앱에서도 이어서 볼 수 있습니다.
- attach 터미널만 닫으면 클라이언트만 종료되고, 스케줄러 서버와 모바일 접속은 유지됩니다.
- Windows Terminal(`wt.exe`)이 있으면 그것으로 열고, 없으면 PowerShell 창으로 엽니다.
- Windows 11에서는 메뉴가 **더 많은 옵션 표시** 쪽에 나타날 수 있습니다.

Windows OpenCode Desktop에 서버를 `CLI Server`라는 추가 연결로 등록하려면 [Windows Desktop CLI Server 등록](WINDOWS-DESKTOP-CLI-SERVER.md)을 참고하세요.

## 접속 및 보안

서버는 LAN 접속을 위해 `0.0.0.0`에 바인딩되며 HTTP Basic Auth 비밀번호를 사용합니다. HTTPS가 아니므로 신뢰할 수 있는 네트워크에서만 사용하세요. 로컬 PC에서만 접근할 필요가 있다면 각 스크립트의 `--hostname 0.0.0.0`을 `--hostname 127.0.0.1`로 바꾸세요.

서버 문서는 `http://localhost:4096/doc`에서 확인할 수 있습니다.
