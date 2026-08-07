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
UPDATE_PATH="$BIN_DIR/opencode-update"
SETTINGS_PATH="$CONFIG_DIR/server-settings.json"
UPDATE_LOG_PATH="$LOG_DIR/opencode-update.log"
COUNTER_PATH="$CONFIG_DIR/server-restart-count"

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

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  print -r -- "$s"
}

# Returns the raw JSON value (true/false or a quoted string) for a key, or empty.
read_setting() {
  local key="$1"
  if [[ ! -f "$SETTINGS_PATH" ]]; then
    return 0
  fi
  sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\([^,}]*\).*/\1/p" "$SETTINGS_PATH" 2>/dev/null | head -n 1 || true
}

write_setting() {
  local key="$1" value="$2" json_value k
  if [[ "$value" == "true" || "$value" == "false" ]]; then
    json_value="$value"
  else
    json_value="\"$(json_escape "$value")\""
  fi

  local -A settings
  settings[autoUpdate]="$(read_setting autoUpdate)"
  settings[autoApprove]="$(read_setting autoApprove)"
  settings[opencodePath]="$(read_setting opencodePath)"
  settings[$key]="$json_value"

  local -a entries
  for k in autoUpdate autoApprove opencodePath; do
    if [[ -n "${settings[$k]}" ]]; then
      entries+=("\"$k\": ${settings[$k]}")
    fi
  done

  mkdir -p "$CONFIG_DIR"
  umask 077
  printf '{%s}\n' "$(IFS=,; print -r -- "${entries[*]}")" > "$SETTINGS_PATH.tmp"
  mv -f "$SETTINGS_PATH.tmp" "$SETTINGS_PATH"
  chmod 600 "$SETTINGS_PATH"
}

# Finds the opencode executable, ignoring aliases and functions like Get-Command does on Windows.
find_opencode() {
  local bin
  bin="$(whence -p opencode 2>/dev/null || true)"
  if [[ -z "$bin" ]]; then
    bin="$(command -v opencode 2>/dev/null || true)"
    if [[ -n "$bin" && ! -x "$bin" ]]; then
      bin=""
    fi
  fi
  print -r -- "$bin"
}

setting_is_true() {
  local key="$1" value
  if [[ -f "$SETTINGS_PATH" ]]; then
    value="$(sed -nE "s/.*\"$key\"[[:space:]]*:[[:space:]]*(true|false).*/\1/p" "$SETTINGS_PATH" 2>/dev/null | head -n 1 || true)"
    [[ "$value" == "true" ]] && return 0
  fi
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

  opencode_bin="$(find_opencode)"
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

  print -n "로그온 시 opencode 자동 업데이트? [Y/n]: "
  read -r auto_update
  if [[ "${auto_update:l}" == "n" || "${auto_update:l}" == "no" ]]; then
    write_setting autoUpdate false
  else
    write_setting autoUpdate true
  fi

  print -n "서버 자동 승인(모든 권한 허용)을 사용할까요? [Y/n]: "
  read -r auto_approve
  if [[ "${auto_approve:l}" == "n" || "${auto_approve:l}" == "no" ]]; then
    write_setting autoApprove false
  else
    write_setting autoApprove true
  fi
  write_setting opencodePath "$opencode_bin"

  mkdir -p "$LAUNCH_AGENTS_DIR" "$BIN_DIR" "$LOG_DIR" "$SERVICES_DIR"

  printf '%s\n' '#!/bin/zsh' 'set -euo pipefail' \
    "export PATH=${(q)service_path}" \
    "opencode_bin=${(q)opencode_bin}" \
    'count_file="$HOME/.config/opencode/server-restart-count"' \
    'count=1' \
    'if [[ -f "$count_file" ]]; then' \
    '  count="$(<"$count_file" 2>/dev/null || print 1)"' \
    '  [[ "$count" =~ "^[0-9]+$" ]] || count=1' \
    '  if (( $(date +%s) - $(stat -f %m "$count_file" 2>/dev/null || print 0) > 60 )); then count=1; else count=$((count + 1)); fi' \
    'fi' \
    'if (( count > 4 )); then' \
    '  rm -f "$count_file"' \
    '  print -u2 "[$(date "+%Y-%m-%d %H:%M:%S")] OpenCode 서버가 3회 연속 실패하여 재시도를 중단합니다."' \
    '  exit 0' \
    'fi' \
    'print "$count" > "$count_file" 2>/dev/null || true' \
    'password_file="$HOME/.config/opencode/server-password"' \
    '[[ -r "$password_file" ]] || { print -u2 "OpenCode server password file is missing."; exit 1; }' \
    'export OPENCODE_SERVER_PASSWORD="$(< "$password_file")"' \
    'settings_file="$HOME/.config/opencode/server-settings.json"' \
    'if [[ -f "$settings_file" ]] && [[ "$(sed -nE '\''s/.*"autoApprove"[[:space:]]*:[[:space:]]*(true|false).*/\1/p'\'' "$settings_file" 2>/dev/null | head -n 1)" == "true" ]]; then' \
    '  export OPENCODE_PERMISSION="{\"*\": \"allow\"}"' \
    'fi' \
    'update_script="$HOME/.local/bin/opencode-update"' \
    'if [[ -x "$update_script" ]]; then' \
    '  if ! "$update_script" "$opencode_bin" >/dev/null 2>&1; then' \
    '    print -u2 "[$(date "+%Y-%m-%d %H:%M:%S")] opencode 자동 업데이트에 실패했습니다."' \
    '  fi' \
    'fi' \
    "exec \"\$opencode_bin\" serve --hostname 0.0.0.0 --port ${(q)port}" > "$WRAPPER_PATH"
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

  cat > "$UPDATE_PATH" <<'UPDATE_SCRIPT'
#!/bin/zsh
# opencode 자동 업데이트 (opencode-server 래퍼가 서버 시작 전에 호출)

set -u

opencode_bin="${1:-}"
settings_path="$HOME/.config/opencode/server-settings.json"
log_path="$HOME/Library/Logs/OpenCode/opencode-update.log"
timeout_seconds=300

log_line() {
  local line
  line="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  print -r -- "$line" >> "$log_path" 2>/dev/null || true
}

detect_update_command() {
  local opencode_bin="$1" prefix value

  if command -v brew >/dev/null 2>&1; then
    prefix="$(brew --prefix 2>/dev/null || true)"
    if [[ -n "$prefix" && "$opencode_bin" == "$prefix"/* ]]; then
      if brew list --cask opencode >/dev/null 2>&1; then
        print -- "brew-cask"
        return 0
      fi
      print -- "brew"
      return 0
    fi
  fi

  if command -v npm >/dev/null 2>&1; then
    prefix="$(npm prefix -g 2>/dev/null || true)"
    if [[ -n "$prefix" && "$opencode_bin" == "$prefix"/bin/opencode* ]]; then
      print -- "npm"
      return 0
    fi
  fi

  if command -v pnpm >/dev/null 2>&1; then
    prefix="$(pnpm bin -g 2>/dev/null || true)"
    if [[ -n "$prefix" && "$opencode_bin" == "$prefix"/opencode* ]]; then
      print -- "pnpm"
      return 0
    fi
  fi

  if command -v yarn >/dev/null 2>&1; then
    prefix="$(yarn global bin 2>/dev/null || true)"
    if [[ -n "$prefix" && "$opencode_bin" == "$prefix"/opencode* ]]; then
      print -- "yarn"
      return 0
    fi
  fi

  if command -v bun >/dev/null 2>&1; then
    prefix="$(bun pm bin -g 2>/dev/null || true)"
    if [[ -n "$prefix" && "$opencode_bin" == "$prefix"/opencode* ]]; then
      print -- "bun"
      return 0
    fi
  fi

  print -- "self"
  return 0
}

run_update() {
  local tool="$1" opencode_bin="$2"
  local -a cmd
  local pid exit_code elapsed=0 out_file

  case "$tool" in
    brew)      cmd=(/bin/zsh -c 'brew update && brew upgrade opencode') ;;
    brew-cask) cmd=(/bin/zsh -c 'brew update && brew upgrade --cask opencode') ;;
    npm)       cmd=(npm install -g opencode-ai@latest) ;;
    pnpm)      cmd=(pnpm add -g opencode-ai@latest) ;;
    yarn)      cmd=(yarn global add opencode-ai@latest) ;;
    bun)       cmd=(bun add -g opencode-ai@latest) ;;
    *)         cmd=("$opencode_bin" upgrade) ;;
  esac

  out_file="$(mktemp /tmp/opencode-update.XXXXXX)" 2>/dev/null || out_file="/tmp/opencode-update.$$"
  ("$cmd[@]" >"$out_file" 2>&1) &
  pid=$!

  while kill -0 "$pid" 2>/dev/null; do
    sleep 1
    (( elapsed += 1 ))
    if (( elapsed >= timeout_seconds )); then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      log_line "업데이트 시간 초과 (${timeout_seconds}초)로 중단했습니다."
      rm -f "$out_file"
      return 0
    fi
  done

  wait "$pid"
  exit_code=$?
  rm -f "$out_file"
  return $exit_code
}

log_line "opencode 업데이트 확인: $opencode_bin"

if [[ ! -x "$opencode_bin" ]]; then
  log_line "opencode 경로가 존재하지 않습니다. 업데이트를 건너뜁니다."
  exit 0
fi

enabled=true
if [[ -f "$settings_path" ]]; then
  value="$(sed -nE 's/.*"autoUpdate"[[:space:]]*:[[:space:]]*(true|false).*/\1/p' "$settings_path")"
  if [[ -n "$value" && "$value" != "true" ]]; then
    enabled=false
  fi
fi

if [[ "$enabled" != "true" ]]; then
  log_line "자동 업데이트가 꺼져 있습니다 (server-settings.json). 건너뜁니다."
  exit 0
fi

tool="$(detect_update_command "$opencode_bin")"
before="$("$opencode_bin" --version 2>/dev/null | head -n 1)"

log_line "감지된 설치 방식: $tool (업데이트 전 버전: $before)"

run_update "$tool" "$opencode_bin"
exit_code=$?

after="$("$opencode_bin" --version 2>/dev/null | head -n 1)"
log_line "업데이트 종료 (exit code $exit_code). 버전: $before -> $after"
exit 0
UPDATE_SCRIPT
  chmod 700 "$UPDATE_PATH"

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
    '  <key>KeepAlive</key>' \
    '  <dict>' \
    '    <key>SuccessfulExit</key>' \
    '    <false/>' \
    '  </dict>' \
    "  <key>StandardOutPath</key><string>$LOG_DIR/opencode-server.out.log</string>" \
    "  <key>StandardErrorPath</key><string>$LOG_DIR/opencode-server.err.log</string>" \
    '</dict>' \
    '</plist>' > "$PLIST_PATH"

  plutil -lint "$PLIST_PATH" >/dev/null
  cleanup_service
  rm -f "$COUNTER_PATH"
  bootstrap_service
  launchctl kickstart -k "$SERVICE_TARGET"

  print "OpenCode 서버를 설치하고 시작했습니다."
  print "LAN 주소: http://$(scutil --get LocalHostName 2>/dev/null || hostname).local:$port"
  print "Finder 빠른 동작: $QUICK_ACTION_NAME (http://127.0.0.1:${port}에 attach)"
  if setting_is_true autoUpdate; then
    print "자동 업데이트: 켜짐 (로그온 시 최신 버전으로 업데이트 후 서버 시작)"
  else
    print "자동 업데이트: 꺼짐"
  fi
  if setting_is_true autoApprove; then
    print "자동 승인(서버 전체 세션): 켜짐 (모든 권한 허용)"
  else
    print "자동 승인: 꺼짐"
  fi
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
  rm -f "$PLIST_PATH" "$WRAPPER_PATH" "$ATTACH_PATH" "$ATTACH_LAUNCHER_PATH" "$UPDATE_PATH" "$PASSWORD_PATH" "$SETTINGS_PATH" "$COUNTER_PATH"
  rm -rf "$QUICK_ACTION_PATH"
  if [[ -x /System/Library/CoreServices/pbs ]]; then
    /System/Library/CoreServices/pbs -flush 2>/dev/null || true
  fi
  print "OpenCode 서버 자동 실행과 Finder 빠른 동작을 삭제했습니다."
}

restart_service() {
  local attempt service_info pid opencode_bin update_script last_exit_code

  if [[ ! -f "$PLIST_PATH" ]]; then
    print "OpenCode 서버가 설치되어 있지 않습니다. 먼저 설치하세요."
    return 1
  fi

  update_script="$BIN_DIR/opencode-update"
  if [[ -x "$update_script" ]]; then
    opencode_bin="$(read_setting opencodePath)"
    if [[ "$opencode_bin" == \"*\" ]]; then
      opencode_bin="${opencode_bin#\"}"
      opencode_bin="${opencode_bin%\"}"
    else
      opencode_bin=""
    fi
    if [[ -z "$opencode_bin" ]]; then
      opencode_bin="$(sed -n 's/^opencode_bin=\(.*\)$/\1/p' "$WRAPPER_PATH" 2>/dev/null | head -n 1)"
      opencode_bin="${opencode_bin#\'}"
      opencode_bin="${opencode_bin%\'}"
    fi
    if [[ -z "$opencode_bin" ]]; then
      opencode_bin="$(find_opencode)"
    fi
    if [[ -n "$opencode_bin" ]]; then
      print "opencode 업데이트를 실행합니다..."
      "$update_script" "$opencode_bin" >/dev/null 2>&1 || true
      print "업데이트 로그: $UPDATE_LOG_PATH"
    fi
  fi

  rm -f "$COUNTER_PATH"
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
  if [[ "$service_info" =~ 'state = ([a-z]+)' ]]; then
    print "상태: $match[1]"
  else
    print "상태: 실행 중이 아님"
  fi
  if [[ "$service_info" =~ 'last exit code = ([0-9-]+)' ]]; then
    print "마지막 종료 코드: $match[1]"
  fi
  print "오류 로그: $LOG_DIR/opencode-server.err.log"
  return 1
}

while true; do
  clear
  print "OpenCode 서버 자동 실행 관리"
  print "1) 설치 또는 다시 설치"
  print "2) 삭제"
  print "3) 업데이트 및 재시작"
  print "4) 자동 업데이트 켜기/끄기"
  print "5) 종료"
  print -n "선택 [1/2/3/4/5]: "
  read -r action

  case "$action" in
    1) install_service || true ;;
    2) remove_service || true ;;
    3) restart_service || true ;;
    4)
      if setting_is_true autoUpdate; then
        write_setting autoUpdate false
        print "자동 업데이트를 껐습니다. (서버 재시작 후 반영)"
      else
        write_setting autoUpdate true
        print "자동 업데이트를 켰습니다. (서버 재시작 후 반영)"
      fi
      ;;
    5) break ;;
    *) print "올바른 번호를 선택하세요." ;;
  esac

  print
  print "계속하려면 Return 키를 누르세요."
  read -r
done
