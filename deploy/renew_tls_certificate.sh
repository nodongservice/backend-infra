#!/usr/bin/env bash
set -Eeuo pipefail

if (( EUID != 0 )); then
  exec sudo -n -- "$0" "$@"
fi

TLS_DOMAIN="${TLS_DOMAIN:-api.bridgework.cloud}"
RENEW_WINDOW_DAYS="${RENEW_WINDOW_DAYS:-21}"
ACME_WEBROOT="${ACME_WEBROOT:-/var/www/certbot}"
ACME_CHALLENGE_DIR="${ACME_WEBROOT}/.well-known/acme-challenge"
CERTIFICATE_PATH="/etc/letsencrypt/live/${TLS_DOMAIN}/fullchain.pem"
RENEWAL_CONFIG="/etc/letsencrypt/renewal/${TLS_DOMAIN}.conf"

if [[ ! "$TLS_DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "유효하지 않은 TLS 도메인입니다: $TLS_DOMAIN" >&2
  exit 1
fi

if [[ ! "$RENEW_WINDOW_DAYS" =~ ^[0-9]+$ ]] || (( RENEW_WINDOW_DAYS < 1 || RENEW_WINDOW_DAYS > 60 )); then
  echo "RENEW_WINDOW_DAYS는 1부터 60 사이의 정수여야 합니다." >&2
  exit 1
fi

RENEW_WINDOW_SECONDS=$((RENEW_WINDOW_DAYS * 86400))

for required_command in certbot nginx openssl systemctl curl; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "필수 명령을 찾을 수 없습니다: $required_command" >&2
    exit 1
  fi
done

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

served_probe="$(curl --fail --silent --show-error --max-time 15 \
  --resolve "${TLS_DOMAIN}:80:127.0.0.1" \
  "http://${TLS_DOMAIN}/.well-known/acme-challenge/${probe_name}")"

if [[ "$served_probe" != "$probe_value" ]]; then
  echo "Nginx ACME challenge 경로 검증에 실패했습니다." >&2
  exit 1
fi

cleanup_probe
trap - EXIT

# 기존 standalone 설정을 공개 경로 검증 후 webroot 방식으로 영구 전환한다.
if ! grep -Eq '^[[:space:]]*authenticator[[:space:]]*=[[:space:]]*webroot[[:space:]]*$' "$RENEWAL_CONFIG"; then
  certbot reconfigure \
    --cert-name "$TLS_DOMAIN" \
    --webroot \
    --webroot-path "$ACME_WEBROOT" \
    --non-interactive
fi

certbot renew --cert-name "$TLS_DOMAIN" --non-interactive

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
