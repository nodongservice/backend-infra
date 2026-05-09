#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

TARGET_SLOT="${1:-${SPRING_TARGET_SLOT:-}}"
if [[ -z "$TARGET_SLOT" ]]; then
  log "사용법: spring_blue_green_switch.sh <blue|green>"
  log "또는 SPRING_TARGET_SLOT 환경변수를 지정하세요."
  exit 1
fi

if [[ "$TARGET_SLOT" != "blue" && "$TARGET_SLOT" != "green" ]]; then
  log "TARGET_SLOT 값이 올바르지 않습니다: $TARGET_SLOT (blue|green)"
  exit 1
fi

SPRING_STATE_DIR="${SPRING_STATE_DIR:-$HOME/bridgework/backend/state}"
SPRING_ACTIVE_SLOT_FILE="${SPRING_ACTIVE_SLOT_FILE:-$SPRING_STATE_DIR/active_slot}"
SPRING_BLUE_PORT="${SPRING_BLUE_PORT:-18080}"
SPRING_GREEN_PORT="${SPRING_GREEN_PORT:-18081}"
SPRING_NGINX_UPSTREAM_CONF="${SPRING_NGINX_UPSTREAM_CONF:-}"

resolve_spring_upstream_conf_path() {
  if [[ -n "$SPRING_NGINX_UPSTREAM_CONF" ]]; then
    echo "$SPRING_NGINX_UPSTREAM_CONF"
    return
  fi

  if [[ -f "/etc/nginx/conf.d/bridgework-upstream.inc" || -d "/etc/nginx/conf.d" ]]; then
    echo "/etc/nginx/conf.d/bridgework-upstream.inc"
    return
  fi

  if [[ -f "/etc/nginx/sites-enabled/bridgework-upstream.inc" || -d "/etc/nginx/sites-enabled" ]]; then
    echo "/etc/nginx/sites-enabled/bridgework-upstream.inc"
    return
  fi

  echo "/etc/nginx/conf.d/bridgework-upstream.inc"
}

SPRING_NGINX_UPSTREAM_CONF="$(resolve_spring_upstream_conf_path)"

if [[ "$TARGET_SLOT" == "blue" ]]; then
  TARGET_PORT="$SPRING_BLUE_PORT"
else
  TARGET_PORT="$SPRING_GREEN_PORT"
fi

mkdir -p "$SPRING_STATE_DIR"

TMP_UPSTREAM_FILE="$(mktemp)"
cat > "$TMP_UPSTREAM_FILE" <<UPSTREAM
upstream bridgework_backend {
    server 127.0.0.1:${TARGET_PORT};
    keepalive 64;
}
UPSTREAM

PREV_UPSTREAM_FILE=""
if sudo test -f "$SPRING_NGINX_UPSTREAM_CONF"; then
  PREV_UPSTREAM_FILE="$(mktemp)"
  sudo cp "$SPRING_NGINX_UPSTREAM_CONF" "$PREV_UPSTREAM_FILE"
fi

log "Spring upstream 전환: slot=${TARGET_SLOT}, port=${TARGET_PORT}"
sudo cp "$TMP_UPSTREAM_FILE" "$SPRING_NGINX_UPSTREAM_CONF"
rm -f "$TMP_UPSTREAM_FILE"

if ! sudo nginx -t >/dev/null 2>&1; then
  log "nginx 설정 검증 실패. 이전 Spring upstream으로 롤백합니다."
  if [[ -n "$PREV_UPSTREAM_FILE" ]]; then
    sudo cp "$PREV_UPSTREAM_FILE" "$SPRING_NGINX_UPSTREAM_CONF"
  fi
  exit 1
fi

sudo systemctl reload nginx
echo "$TARGET_SLOT" > "$SPRING_ACTIVE_SLOT_FILE"

if [[ -n "$PREV_UPSTREAM_FILE" ]]; then
  rm -f "$PREV_UPSTREAM_FILE"
fi

log "Spring upstream 전환 완료: active_slot=${TARGET_SLOT}"
