#!/bin/zsh
# Double-click this file in Finder to install or remove the OpenCode server service.

set -euo pipefail

LABEL="com.anomalyco.opencode-server"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENTS_DIR/$LABEL.plist"
BIN_DIR="$HOME/.local/bin"
WRAPPER_PATH="$BIN_DIR/opencode-server"
CONFIG_DIR="$HOME/.config/opencode"
PASSWORD_PATH="$CONFIG_DIR/server-password"
LOG_DIR="$HOME/Library/Logs/OpenCode"
SERVICE_TARGET="gui/$UID/$LABEL"

cleanup_service() {
  launchctl bootout "$SERVICE_TARGET" 2>/dev/null || true
}

install_service() {
  local opencode_bin port password confirm

  opencode_bin="$(command -v opencode || true)"
  if [[ -z "$opencode_bin" ]]; then
    print "OpenCode CLI를 찾지 못했습니다. 먼저 OpenCode를 설치하세요."
    print "  Homebrew: brew install anomalyco/tap/opencode"
    print "  npm:      npm install -g opencode-ai"
    return 1
  fi

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

  mkdir -p "$LAUNCH_AGENTS_DIR" "$BIN_DIR" "$LOG_DIR"

  printf '%s\n' '#!/bin/zsh' 'set -euo pipefail' \
    'password_file="$HOME/.config/opencode/server-password"' \
    '[[ -r "$password_file" ]] || { print -u2 "OpenCode server password file is missing."; exit 1; }' \
    'export OPENCODE_SERVER_PASSWORD="$(< "$password_file")"' \
    "exec ${(q)opencode_bin} serve --hostname 0.0.0.0 --port ${(q)port}" > "$WRAPPER_PATH"
  chmod 700 "$WRAPPER_PATH"

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
  launchctl bootstrap "gui/$UID" "$PLIST_PATH"
  launchctl kickstart -k "$SERVICE_TARGET"

  print "OpenCode 서버를 설치하고 시작했습니다."
  print "LAN 주소: http://$(scutil --get LocalHostName 2>/dev/null || hostname).local:$port"
  print "상태 확인: launchctl print $SERVICE_TARGET"
}

remove_service() {
  local confirm
  print -n "서버 등록, 실행 스크립트, 저장된 비밀번호를 삭제합니다. 계속할까요? [y/N]: "
  read -r confirm
  if [[ "${confirm:l}" != "y" && "${confirm:l}" != "yes" ]]; then
    print "취소했습니다."
    return 0
  fi

  cleanup_service
  rm -f "$PLIST_PATH" "$WRAPPER_PATH" "$PASSWORD_PATH"
  print "OpenCode 서버 자동 실행을 삭제했습니다."
}

clear
print "OpenCode 서버 자동 실행 관리"
print "1) 설치 또는 다시 설치"
print "2) 삭제"
print -n "선택 [1/2]: "
read -r action

case "$action" in
  1) install_service ;;
  2) remove_service ;;
  *) print "올바른 번호를 선택하세요."; exit 1 ;;
esac

print
print "계속하려면 Return 키를 누르세요."
read -r
