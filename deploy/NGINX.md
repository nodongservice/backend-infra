# Nginx 운영 가이드 (BridgeWork API)

이 문서는 `api.bridgework.cloud`에서 동작하는 Nginx 설정 기준서입니다.  
Spring/FastAPI 개발자가 같은 기준으로 라우팅을 유지하도록 작성했습니다.

## 1) 설정 소스

- 템플릿 파일: `deploy/nginx/bridgework.conf`
- Spring 업스트림 파일: `deploy/nginx/bridgework-upstream.inc`
- FastAPI 업스트림 파일: `deploy/nginx/fastapi-upstream.inc`
- 서버 반영 스크립트: `deploy/setup_nginx.sh`
- Spring 업스트림 전환 스크립트: `deploy/spring_blue_green_switch.sh`
- FastAPI 업스트림 전환 스크립트: `deploy/fastapi_blue_green_switch.sh`

`setup_nginx.sh` 실행 시 템플릿이 서버 설정으로 복사됩니다.  
서버에서 직접 수정한 `bridgework.conf`는 다음 배포 때 덮어써집니다.

## 2) 도메인/HTTPS

- 도메인: `api.bridgework.cloud`
- HTTP(`80`) 요청: Host와 무관하게 `https://api.bridgework.cloud`로 301 리다이렉트
- `api.bridgework.cloud/.well-known/acme-challenge/*`만 Certbot webroot에서 HTTP로 제공
- HTTPS(`443`) 처리: Let’s Encrypt 인증서 사용
  - 비정규 Host 요청은 `https://api.bridgework.cloud`로 301 리다이렉트
  - `/etc/letsencrypt/live/api.bridgework.cloud/fullchain.pem`
  - `/etc/letsencrypt/live/api.bridgework.cloud/privkey.pem`
- `bridgework-cert-renew.timer`가 하루 2회 갱신을 점검합니다.
- GitHub Actions가 매일 별도로 갱신을 점검해 서버 타이머 장애를 보완합니다.
- 갱신 후 배포 훅은 `nginx -t` 통과 시에만 Nginx를 reload합니다.
- 기존 `standalone` 갱신 설정은 공개 경로 검증 후 `webroot`로 자동 전환합니다.
- 갱신 전 로컬 HTTP challenge 응답을 검사하므로 잘못된 Nginx 설정에서는 Certbot을 실행하지 않습니다.
- 남은 유효기간이 21일 미만이면 갱신 작업을 실패 처리하고 Discord로 알립니다.

## 3) 라우팅 정책

### 3.1 서비스 라우팅

| 외부 경로 | 내부 대상 |
|---|---|
| `/api/java/v1/*` | Spring `bridgework_backend`의 `/api/v1/*` |
| `/api/java/actuator/*` | Spring `bridgework_backend`의 `/actuator/*` |
| `/api/py/v1/*` | FastAPI `bridgework_fastapi_backend`의 `/api/v1/*` |
| `/api/py/health` | FastAPI `bridgework_fastapi_backend`의 `/health` |
| `/api/py/db-health` | FastAPI `bridgework_fastapi_backend`의 `/db-health` |
| `/api/py/postgis-health` | FastAPI `bridgework_fastapi_backend`의 `/postgis-health` |
| `/api/py/metrics` | FastAPI `bridgework_fastapi_backend`의 `/metrics` |
| `/grafana/*` | Grafana `127.0.0.1:3000` |

### 3.2 Swagger 라우팅

| 외부 경로 | 내부 대상 |
|---|---|
| `/api/java/docs` | Spring Swagger UI 별칭 |
| `/api/java/swagger-ui.html` | Spring Swagger UI |
| `/api/java/v3/api-docs` | Spring OpenAPI JSON |
| `/api/py/docs` | FastAPI Swagger UI |
| `/api/py/openapi.json` | FastAPI OpenAPI JSON |

FastAPI docs 페이지는 기본적으로 `/openapi.json`을 참조하므로,  
Nginx `sub_filter`로 `/api/py/openapi.json`을 참조하도록 재작성합니다.

## 4) 포트/업스트림

### 4.1 Spring (무중단 블루그린)

- 컨테이너 내부 포트: `8080`
- 호스트 포트 슬롯: `18080(blue)`, `18081(green)`
- Nginx는 `bridgework-upstream.inc`를 참조
- Spring 배포 파이프라인은 새 슬롯 컨테이너 기동/헬스체크 후
  `spring_blue_green_switch.sh <blue|green>`으로 트래픽을 전환

### 4.2 FastAPI (별도 파이프라인)

- 컨테이너 내부 포트: `8000`
- 호스트 포트 슬롯: `19000`, `19001`
- Nginx는 `fastapi-upstream.inc`를 참조
- FastAPI 배포 파이프라인은 새 슬롯 컨테이너 기동/헬스체크 후  
  `fastapi_blue_green_switch.sh <blue|green>`으로 트래픽을 전환

### 4.3 FastAPI 슬롯 전환 예시

```bash
# blue 슬롯(19000)으로 전환
bash deploy/fastapi_blue_green_switch.sh blue

# green 슬롯(19001)으로 전환
bash deploy/fastapi_blue_green_switch.sh green
```

### 4.4 Spring 슬롯 전환 예시

```bash
# blue 슬롯(18080)으로 전환
bash deploy/spring_blue_green_switch.sh blue

# green 슬롯(18081)으로 전환
bash deploy/spring_blue_green_switch.sh green
```

## 5) FastAPI 개발자 참고

### 5.1 유지해야 할 내부 경로 기준

- API prefix: `/api/v1/*`
- Docs: `/docs`
- OpenAPI JSON: `/openapi.json`

외부 노출 경로(`/api/py/...`)는 Nginx가 담당합니다.  
FastAPI 코드에 `api/py` prefix를 직접 넣지 마세요.

### 5.2 바꾸면 Nginx도 같이 수정해야 하는 항목

| FastAPI 변경 항목 | Nginx 수정 필요 |
|---|---|
| `docs_url` 변경 | `/api/py/docs` 라우팅 |
| `openapi_url` 변경 | `/api/py/openapi.json` 라우팅 및 `sub_filter` |
| API prefix 변경 | `/api/py/v1/` 라우팅 대상 |
| 내부 포트 변경(8000 외) | `bridgework_fastapi_backend` 업스트림 포트 |

## 6) 운영 체크 명령

```bash
sudo nginx -t
sudo systemctl reload nginx
sudo systemctl status nginx --no-pager
sudo systemctl status bridgework-cert-renew.timer --no-pager
sudo /usr/local/sbin/bridgework-renew-tls
```

```bash
curl -I https://api.bridgework.cloud
curl -sS https://api.bridgework.cloud/api/java/v3/api-docs | head
curl -sS https://api.bridgework.cloud/api/py/openapi.json | head
```

## 7) 장애 시 우선 확인

1. `nginx -t` 문법 오류 여부
2. 인증서 경로 존재 여부 (`/etc/letsencrypt/live/api.bridgework.cloud/...`)
3. Spring 활성 슬롯 포트와 `bridgework-upstream.inc` 일치 여부
4. FastAPI 활성 슬롯 포트와 `fastapi-upstream.inc` 일치 여부
5. 보안그룹에서 `80`, `443` 허용 여부
