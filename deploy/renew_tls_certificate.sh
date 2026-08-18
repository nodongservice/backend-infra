#!/usr/bin/env bash
set -Eeuo pipefail

if (( EUID != 0 )); then
  exec sudo -n -- "$0" "$@"
fi

TLS_DOMAIN="${TLS_DOMAIN:-api.bridgework.cloud}"
RENEW_WINDOW_DAYS="${RENEW_WINDOW_DAYS:-21}"
CERTIFICATE_PATH="/etc/letsencrypt/live/${TLS_DOMAIN}/fullchain.pem"

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

# 기존 발급 설정을 재사용하므로 인증 방식과 도메인 구성이 바뀌지 않는다.
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
