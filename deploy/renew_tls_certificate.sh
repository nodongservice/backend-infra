#!/usr/bin/env bash
set -Eeuo pipefail

if (( EUID != 0 )); then
  exec sudo -n -- "$0" "$@"
fi

TLS_DOMAIN="${TLS_DOMAIN:-api.bridgework.cloud}"
RENEW_WINDOW_DAYS="${RENEW_WINDOW_DAYS:-21}"
CERTBOT_LOCK_RETRY_ATTEMPTS="${CERTBOT_LOCK_RETRY_ATTEMPTS:-12}"
CERTBOT_LOCK_RETRY_DELAY_SECONDS="${CERTBOT_LOCK_RETRY_DELAY_SECONDS:-10}"
ACME_WEBROOT="${ACME_WEBROOT:-/var/www/certbot}"
ACME_CHALLENGE_DIR="${ACME_WEBROOT}/.well-known/acme-challenge"
CERTIFICATE_PATH="/etc/letsencrypt/live/${TLS_DOMAIN}/fullchain.pem"
RENEWAL_CONFIG="/etc/letsencrypt/renewal/${TLS_DOMAIN}.conf"
PROCESS_LOCK_FILE="/run/lock/bridgework-cert-renew.lock"

if [[ ! "$TLS_DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "유효하지 않은 TLS 도메인입니다: $TLS_DOMAIN" >&2
  exit 1
fi

if [[ ! "$RENEW_WINDOW_DAYS" =~ ^[0-9]+$ ]] || (( RENEW_WINDOW_DAYS < 1 || RENEW_WINDOW_DAYS > 60 )); then
  echo "RENEW_WINDOW_DAYS는 1부터 60 사이의 정수여야 합니다." >&2
  exit 1
fi

if [[ ! "$CERTBOT_LOCK_RETRY_ATTEMPTS" =~ ^[0-9]+$ ]] || (( CERTBOT_LOCK_RETRY_ATTEMPTS < 1 || CERTBOT_LOCK_RETRY_ATTEMPTS > 60 )); then
  echo "CERTBOT_LOCK_RETRY_ATTEMPTS는 1부터 60 사이의 정수여야 합니다." >&2
  exit 1
fi

if [[ ! "$CERTBOT_LOCK_RETRY_DELAY_SECONDS" =~ ^[0-9]+$ ]] || (( CERTBOT_LOCK_RETRY_DELAY_SECONDS < 1 || CERTBOT_LOCK_RETRY_DELAY_SECONDS > 60 )); then
  echo "CERTBOT_LOCK_RETRY_DELAY_SECONDS는 1부터 60 사이의 정수여야 합니다." >&2
  exit 1
fi

RENEW_WINDOW_SECONDS=$((RENEW_WINDOW_DAYS * 86400))

for required_command in certbot nginx openssl systemctl curl flock; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "필수 명령을 찾을 수 없습니다: $required_command" >&2
    exit 1
  fi
done

# 전용 timer와 GitHub Actions가 겹쳐도 하나의 갱신 작업만 실행한다.
exec {process_lock_fd}>"$PROCESS_LOCK_FILE"
if ! flock --exclusive --wait 300 "$process_lock_fd"; then
  echo "TLS 갱신 프로세스 잠금 대기 시간이 초과되었습니다." >&2
  exit 1
fi

run_certbot() {
  local attempt output exit_code

  for ((attempt = 1; attempt <= CERTBOT_LOCK_RETRY_ATTEMPTS; attempt++)); do
    if output="$(certbot "$@" 2>&1)"; then
      printf '%s\n' "$output"
      return 0
    else
      exit_code=$?
    fi

    printf '%s\n' "$output" >&2

    if [[ "$output" != *"Another instance of Certbot is already running."* ]] || (( attempt == CERTBOT_LOCK_RETRY_ATTEMPTS )); then
      return "$exit_code"
    fi

    echo "다른 Certbot 작업이 실행 중입니다. ${CERTBOT_LOCK_RETRY_DELAY_SECONDS}초 후 재시도합니다. (${attempt}/${CERTBOT_LOCK_RETRY_ATTEMPTS})" >&2
    sleep "$CERTBOT_LOCK_RETRY_DELAY_SECONDS"
  done
}

if [[ ! -r "$CERTIFICATE_PATH" ]]; then
  echo "인증서 파일을 읽을 수 없습니다: $CERTIFICATE_PATH" >&2
  exit 1
fi

if [[ ! -r "$RENEWAL_CONFIG" ]]; then
  echo "Certbot 갱신 설정을 읽을 수 없습니다: $RENEWAL_CONFIG" >&2
  exit 1
fi

if [[ ! -d "$ACME_CHALLENGE_DIR" ]]; then
  echo "ACME challenge 디렉터리를 찾을 수 없습니다: $ACME_CHALLENGE_DIR" >&2
  exit 1
fi

# Certbot 실행 전에 Nginx가 HTTP-01 파일을 실제 제공하는지 확인한다.
probe_name="bridgework-$(openssl rand -hex 16)"
probe_path="${ACME_CHALLENGE_DIR}/${probe_name}"
probe_value="${probe_name}-ok"

cleanup_probe() {
  rm -f -- "$probe_path"
}
trap cleanup_probe EXIT

printf '%s' "$probe_value" >"$probe_path"
chmod 0644 "$probe_path"

challenge_ready=false
for attempt in 1 2 3 4 5; do
  if served_probe="$(curl --fail --silent --show-error --max-time 15 \
    --noproxy '*' \
    --resolve "${TLS_DOMAIN}:80:127.0.0.1" \
    "http://${TLS_DOMAIN}/.well-known/acme-challenge/${probe_name}")" \
    && [[ "$served_probe" == "$probe_value" ]]; then
    challenge_ready=true
    break
  fi

  if (( attempt < 5 )); then
    sleep "$attempt"
  fi
done

if [[ "$challenge_ready" != true ]]; then
  echo "Nginx ACME challenge 경로 검증에 실패했습니다." >&2
  exit 1
fi

cleanup_probe
trap - EXIT

# 기존 standalone 설정을 공개 경로 검증 후 webroot 방식으로 영구 전환한다.
if ! grep -Eq '^[[:space:]]*authenticator[[:space:]]*=[[:space:]]*webroot[[:space:]]*$' "$RENEWAL_CONFIG"; then
  run_certbot reconfigure \
    --cert-name "$TLS_DOMAIN" \
    --webroot \
    --webroot-path "$ACME_WEBROOT" \
    --non-interactive
fi

run_certbot renew --cert-name "$TLS_DOMAIN" --non-interactive

nginx -t
systemctl reload nginx

if ! openssl x509 -checkend "$RENEW_WINDOW_SECONDS" -noout -in "$CERTIFICATE_PATH"; then
  echo "TLS 인증서 유효기간이 ${RENEW_WINDOW_DAYS}일 미만입니다." >&2
  openssl x509 -noout -subject -issuer -dates -in "$CERTIFICATE_PATH" >&2
  exit 1
fi

# DNS 경로를 우회하고 이 서버가 새 인증서를 실제 제공하는지 확인한다.
curl --silent --show-error --head --max-time 15 \
  --resolve "${TLS_DOMAIN}:443:127.0.0.1" \
  "https://${TLS_DOMAIN}/" >/dev/null

openssl x509 -noout -subject -issuer -dates -in "$CERTIFICATE_PATH"
echo "TLS 인증서 갱신 점검 완료: $TLS_DOMAIN"
