#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

TARGET_SLOT="${1:-${FASTAPI_TARGET_SLOT:-}}"
if [[ -z "$TARGET_SLOT" ]]; then
  log "사용법: fastapi_blue_green_switch.sh <blue|green>"
  log "또는 FASTAPI_TARGET_SLOT 환경변수를 지정하세요."
  exit 1
fi

if [[ "$TARGET_SLOT" != "blue" && "$TARGET_SLOT" != "green" ]]; then
  log "TARGET_SLOT 값이 올바르지 않습니다: $TARGET_SLOT (blue|green)"
  exit 1
fi

FASTAPI_STATE_DIR="${FASTAPI_STATE_DIR:-$HOME/bridgework/state}"
FASTAPI_ACTIVE_SLOT_FILE="${FASTAPI_ACTIVE_SLOT_FILE:-$FASTAPI_STATE_DIR/fastapi_active_slot}"
FASTAPI_BLUE_PORT="${FASTAPI_BLUE_PORT:-19000}"
FASTAPI_GREEN_PORT="${FASTAPI_GREEN_PORT:-19001}"
FASTAPI_NGINX_UPSTREAM_CONF="${FASTAPI_NGINX_UPSTREAM_CONF:-}"

resolve_fastapi_upstream_conf_path() {
  if [[ -n "$FASTAPI_NGINX_UPSTREAM_CONF" ]]; then
    echo "$FASTAPI_NGINX_UPSTREAM_CONF"
    return
  fi

  if [[ -f "/etc/nginx/conf.d/fastapi-upstream.inc" || -d "/etc/nginx/conf.d" ]]; then
    echo "/etc/nginx/conf.d/fastapi-upstream.inc"
    return
  fi

  if [[ -f "/etc/nginx/sites-enabled/fastapi-upstream.inc" || -d "/etc/nginx/sites-enabled" ]]; then
    echo "/etc/nginx/sites-enabled/fastapi-upstream.inc"
    return
  fi

  echo "/etc/nginx/conf.d/fastapi-upstream.inc"
}

FASTAPI_NGINX_UPSTREAM_CONF="$(resolve_fastapi_upstream_conf_path)"

if [[ "$TARGET_SLOT" == "blue" ]]; then
  TARGET_PORT="$FASTAPI_BLUE_PORT"
else
  TARGET_PORT="$FASTAPI_GREEN_PORT"
fi

mkdir -p "$FASTAPI_STATE_DIR"

TMP_UPSTREAM_FILE="$(mktemp)"
cat > "$TMP_UPSTREAM_FILE" <<UPSTREAM
upstream bridgework_fastapi_backend {
    server 127.0.0.1:${TARGET_PORT};
    keepalive 64;
}
UPSTREAM

PREV_UPSTREAM_FILE=""
if sudo test -f "$FASTAPI_NGINX_UPSTREAM_CONF"; then
  PREV_UPSTREAM_FILE="$(mktemp)"
  sudo cp "$FASTAPI_NGINX_UPSTREAM_CONF" "$PREV_UPSTREAM_FILE"
fi

log "FastAPI upstream 전환: slot=${TARGET_SLOT}, port=${TARGET_PORT}"
sudo cp "$TMP_UPSTREAM_FILE" "$FASTAPI_NGINX_UPSTREAM_CONF"
rm -f "$TMP_UPSTREAM_FILE"

if ! sudo nginx -t >/dev/null 2>&1; then
  log "nginx 설정 검증 실패. 이전 FastAPI upstream으로 롤백합니다."
  if [[ -n "$PREV_UPSTREAM_FILE" ]]; then
    sudo cp "$PREV_UPSTREAM_FILE" "$FASTAPI_NGINX_UPSTREAM_CONF"
  fi
  exit 1
fi

sudo systemctl reload nginx
echo "$TARGET_SLOT" > "$FASTAPI_ACTIVE_SLOT_FILE"

if [[ -n "$PREV_UPSTREAM_FILE" ]]; then
  rm -f "$PREV_UPSTREAM_FILE"
fi

log "FastAPI upstream 전환 완료: active_slot=${TARGET_SLOT}"
