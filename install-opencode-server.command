#!/bin/zsh
# Double-click this file in Finder to install or remove the OpenCode server service.

set -euo pipefail

LABEL="com.anomalyco.opencode-server"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENTS_DIR/$LABEL.plist"
BIN_DIR="$HOME/.local/bin"
WRAPPER_PATH="$BIN_DIR/opencode-server"
ATTACH_PATH="$BIN_DIR/opencode-attach"
ATTACH_LAUNCHER_PATH="$BIN_DIR/opencode-attach-launcher"
CONFIG_DIR="$HOME/.config/opencode"
PASSWORD_PATH="$CONFIG_DIR/server-password"
LOG_DIR="$HOME/Library/Logs/OpenCode"
SERVICES_DIR="$HOME/Library/Services"
QUICK_ACTION_NAME="OpenCode에서 열기"
QUICK_ACTION_PATH="$SERVICES_DIR/$QUICK_ACTION_NAME.workflow"
SERVICE_TARGET="gui/$UID/$LABEL"

cleanup_service() {
  local attempt

  launchctl bootout "$SERVICE_TARGET" 2>/dev/null || true
  for attempt in {1..20}; do
    launchctl print "$SERVICE_TARGET" >/dev/null 2>&1 || return 0
    sleep 0.1
  done
}

bootstrap_service() {
  local attempt bootstrap_error

  for attempt in {1..20}; do
    if bootstrap_error="$(launchctl bootstrap "gui/$UID" "$PLIST_PATH" 2>&1)"; then
      return 0
    fi
    sleep 0.25
  done

  print -u2 "$bootstrap_error"
  return 1
}

install_quick_action() {
  rm -rf "$QUICK_ACTION_PATH"
  mkdir -p "$QUICK_ACTION_PATH/Contents"

  cat > "$QUICK_ACTION_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.anomalyco.opencode-attach.quickaction</string>
  <key>CFBundleName</key>
  <string>OpenCode에서 열기</string>
  <key>NSServices</key>
  <array>
    <dict>
      <key>NSMenuItem</key>
      <dict>
        <key>default</key>
        <string>OpenCode에서 열기</string>
      </dict>
      <key>NSMessage</key>
      <string>runWorkflowAsService</string>
      <key>NSRequiredContext</key>
      <dict>
        <key>NSApplicationIdentifier</key>
        <string>com.apple.finder</string>
      </dict>
      <key>NSSendFileTypes</key>
      <array>
        <string>public.folder</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

  cat > "$QUICK_ACTION_PATH/Contents/document.wflow" <<'WFLOW'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>AMApplicationBuild</key>
  <string>523</string>
  <key>AMApplicationVersion</key>
  <string>2.10</string>
  <key>AMDocumentVersion</key>
  <string>2</string>
  <key>actions</key>
  <array>
    <dict>
      <key>action</key>
      <dict>
        <key>AMAccepts</key>
        <dict>
          <key>Container</key>
          <string>List</string>
          <key>Optional</key>
          <true/>
          <key>Types</key>
          <array>
            <string>com.apple.cocoa.path</string>
          </array>
        </dict>
        <key>AMActionVersion</key>
        <string>2.0.3</string>
        <key>AMApplication</key>
        <array>
          <string>Automator</string>
        </array>
        <key>AMCategory</key>
        <string>AMCategoryUtilities</string>
        <key>AMName</key>
        <string>Run Shell Script</string>
        <key>AMProvides</key>
        <dict>
          <key>Container</key>
          <string>List</string>
          <key>Types</key>
          <array>
            <string>com.apple.cocoa.path</string>
          </array>
        </dict>
        <key>ActionBundlePath</key>
        <string>/System/Library/Automator/Run Shell Script.action</string>
        <key>ActionName</key>
        <string>Run Shell Script</string>
        <key>ActionParameters</key>
        <dict>
          <key>COMMAND_STRING</key>
          <string>"$HOME/.local/bin/opencode-attach-launcher" "$@"</string>
          <key>CheckedForUserDefaultShell</key>
          <true/>
          <key>inputMethod</key>
          <integer>1</integer>
          <key>shell</key>
          <string>/bin/zsh</string>
          <key>source</key>
          <string></string>
        </dict>
        <key>BundleIdentifier</key>
        <string>com.apple.Automator.RunShellScript</string>
        <key>CFBundleVersion</key>
        <string>2.0.3</string>
        <key>CanShowSelectedItemsWhenRun</key>
        <false/>
        <key>CanShowWhenRun</key>
        <true/>
        <key>Category</key>
        <array>
          <string>AMCategoryUtilities</string>
        </array>
        <key>Class Name</key>
        <string>RunShellScriptAction</string>
        <key>InputUUID</key>
        <string>9B7304B6-2CD1-42E2-A20A-28022602E5CC</string>
        <key>OutputUUID</key>
        <string>7D50F2E3-63F6-4AC4-B889-2CF1B7B4DBAB</string>
        <key>UUID</key>
        <string>56361D08-EBF8-4A58-A297-DB44D5D8B058</string>
      </dict>
    </dict>
  </array>
  <key>connectors</key>
  <dict/>
  <key>workflowMetaData</key>
  <dict>
    <key>inputTypeIdentifier</key>
    <string>com.apple.Automator.fileSystemObject</string>
    <key>outputTypeIdentifier</key>
    <string>com.apple.Automator.nothing</string>
    <key>serviceApplicationBundleID</key>
    <string>com.apple.finder</string>
    <key>serviceInputTypeIdentifier</key>
    <string>com.apple.Automator.fileSystemObject</string>
    <key>serviceOutputTypeIdentifier</key>
    <string>com.apple.Automator.nothing</string>
    <key>workflowTypeIdentifier</key>
    <string>com.apple.Automator.servicesMenu</string>
  </dict>
</dict>
</plist>
WFLOW

  plutil -lint "$QUICK_ACTION_PATH/Contents/Info.plist" >/dev/null
  plutil -lint "$QUICK_ACTION_PATH/Contents/document.wflow" >/dev/null
  if [[ -x /System/Library/CoreServices/pbs ]]; then
    /System/Library/CoreServices/pbs -flush 2>/dev/null || true
  fi
}

install_service() {
  local opencode_bin login_path_output login_path line service_path port password confirm

  opencode_bin="$(command -v opencode || true)"
  if [[ -z "$opencode_bin" ]]; then
    print "OpenCode CLI를 찾지 못했습니다. 먼저 OpenCode를 설치하세요."
    print "  Homebrew: brew install anomalyco/tap/opencode"
    print "  npm:      npm install -g opencode-ai"
    return 1
  fi

  login_path_output="$(/bin/zsh -lic 'print -r -- "__OPENCODE_PATH__$PATH"' 2>/dev/null || true)"
  for line in ${(f)login_path_output}; do
    if [[ "$line" == __OPENCODE_PATH__* ]]; then
      login_path="${line#__OPENCODE_PATH__}"
    fi
  done
  service_path="${login_path:+$login_path:}$PATH:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

  print -n "서버 포트 [4096]: "
  read -r port
  port="${port:-4096}"
  if [[ ! "$port" =~ '^[0-9]+$' ]] || (( port < 1 || port > 65535 )); then
    print "포트는 1부터 65535 사이의 숫자여야 합니다."
    return 1
  fi

  if [[ -f "$PASSWORD_PATH" ]]; then
    print -n "기존 서버 비밀번호를 유지할까요? [Y/n]: "
    read -r confirm
    confirm="${confirm:-y}"
  else
    confirm="n"
  fi

  if [[ "${confirm:l}" != "y" && "${confirm:l}" != "yes" ]]; then
    print -n "OpenCode 서버 비밀번호: "
    read -r -s password
    print
    if [[ -z "$password" ]]; then
      print "비밀번호는 비워 둘 수 없습니다."
      return 1
    fi
    mkdir -p "$CONFIG_DIR"
    umask 077
    printf '%s' "$password" > "$PASSWORD_PATH"
    chmod 600 "$PASSWORD_PATH"
  fi

  mkdir -p "$LAUNCH_AGENTS_DIR" "$BIN_DIR" "$LOG_DIR" "$SERVICES_DIR"

  printf '%s\n' '#!/bin/zsh' 'set -euo pipefail' \
    "export PATH=${(q)service_path}" \
    'password_file="$HOME/.config/opencode/server-password"' \
    '[[ -r "$password_file" ]] || { print -u2 "OpenCode server password file is missing."; exit 1; }' \
    'export OPENCODE_SERVER_PASSWORD="$(< "$password_file")"' \
    "exec ${(q)opencode_bin} serve --hostname 0.0.0.0 --port ${(q)port}" > "$WRAPPER_PATH"
  chmod 700 "$WRAPPER_PATH"

  printf '%s\n' '#!/bin/zsh' 'set -euo pipefail' \
    'target_dir="${1:-}"' \
    'password_file="$HOME/.config/opencode/server-password"' \
    "opencode_bin=${(q)opencode_bin}" \
    "server_url=http://127.0.0.1:${(q)port}" \
    '[[ -n "$target_dir" && -d "$target_dir" ]] || { print -u2 "OpenCode attach directory is missing or invalid: $target_dir"; exit 1; }' \
    '[[ -r "$password_file" ]] || { print -u2 "OpenCode server password file is missing. Run the installer first."; exit 1; }' \
    '[[ -x "$opencode_bin" ]] || { print -u2 "OpenCode CLI was not found: $opencode_bin"; exit 1; }' \
    'export OPENCODE_SERVER_PASSWORD="$(< "$password_file")"' \
    'cd "$target_dir"' \
    'exec "$opencode_bin" attach "$server_url" --dir "$target_dir"' > "$ATTACH_PATH"
  chmod 700 "$ATTACH_PATH"

  cat > "$ATTACH_LAUNCHER_PATH" <<'LAUNCHER'
#!/bin/zsh
set -euo pipefail

attach_path="$HOME/.local/bin/opencode-attach"
(( $# > 0 )) || exit 0

for target_dir in "$@"; do
  [[ -d "$target_dir" ]] || continue
  /usr/bin/osascript - "$attach_path" "$target_dir" <<'APPLESCRIPT'
on run argv
  set attachPath to item 1 of argv
  set targetDir to item 2 of argv
  set commandText to quoted form of attachPath & space & quoted form of targetDir

  tell application "Terminal"
    activate
    do script commandText
  end tell
end run
APPLESCRIPT
done
LAUNCHER
  chmod 700 "$ATTACH_LAUNCHER_PATH"

  install_quick_action

  printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0">' \
    '<dict>' \
    "  <key>Label</key><string>$LABEL</string>" \
    "  <key>ProgramArguments</key><array><string>$WRAPPER_PATH</string></array>" \
    "  <key>WorkingDirectory</key><string>$HOME</string>" \
    '  <key>RunAtLoad</key><true/>' \
    '  <key>KeepAlive</key><true/>' \
    "  <key>StandardOutPath</key><string>$LOG_DIR/opencode-server.out.log</string>" \
    "  <key>StandardErrorPath</key><string>$LOG_DIR/opencode-server.err.log</string>" \
    '</dict>' \
    '</plist>' > "$PLIST_PATH"

  plutil -lint "$PLIST_PATH" >/dev/null
  cleanup_service
  bootstrap_service
  launchctl kickstart -k "$SERVICE_TARGET"

  print "OpenCode 서버를 설치하고 시작했습니다."
  print "LAN 주소: http://$(scutil --get LocalHostName 2>/dev/null || hostname).local:$port"
  print "Finder 빠른 동작: $QUICK_ACTION_NAME (http://127.0.0.1:${port}에 attach)"
  print "상태 확인: launchctl print $SERVICE_TARGET"
}

remove_service() {
  local confirm
  print -n "서버 등록, Finder 빠른 동작, 실행 스크립트, 저장된 비밀번호를 삭제합니다. 계속할까요? [y/N]: "
  read -r confirm
  if [[ "${confirm:l}" != "y" && "${confirm:l}" != "yes" ]]; then
    print "취소했습니다."
    return 0
  fi

  cleanup_service
  rm -f "$PLIST_PATH" "$WRAPPER_PATH" "$ATTACH_PATH" "$ATTACH_LAUNCHER_PATH" "$PASSWORD_PATH"
  rm -rf "$QUICK_ACTION_PATH"
  if [[ -x /System/Library/CoreServices/pbs ]]; then
    /System/Library/CoreServices/pbs -flush 2>/dev/null || true
  fi
  print "OpenCode 서버 자동 실행과 Finder 빠른 동작을 삭제했습니다."
}

restart_service() {
  local attempt service_info pid

  if [[ ! -f "$PLIST_PATH" ]]; then
    print "OpenCode 서버가 설치되어 있지 않습니다. 먼저 설치하세요."
    return 1
  fi

  launchctl kickstart -k "$SERVICE_TARGET"
  for attempt in {1..20}; do
    service_info="$(launchctl print "$SERVICE_TARGET" 2>/dev/null || true)"
    if [[ "$service_info" == *"state = running"* ]]; then
      pid="확인할 수 없음"
      if [[ "$service_info" =~ 'pid = ([0-9]+)' ]]; then
        pid="$match[1]"
      fi
      print "OpenCode 서버를 재시작했습니다."
      print "상태: 실행 중 (PID: $pid)"
      return 0
    fi
    sleep 0.25
  done

  print "OpenCode 서버가 재시작 후 정상 실행 상태가 아닙니다."
  print "상태: 실행 중이 아님"
  print "오류 로그: $LOG_DIR/opencode-server.err.log"
  return 1
}

clear
print "OpenCode 서버 자동 실행 관리"
print "1) 설치 또는 다시 설치"
print "2) 삭제"
print "3) 재시작"
print -n "선택 [1/2/3]: "
read -r action

case "$action" in
  1) install_service ;;
  2) remove_service ;;
  3) restart_service ;;
  *) print "올바른 번호를 선택하세요."; exit 1 ;;
esac

print
print "계속하려면 Return 키를 누르세요."
read -r
