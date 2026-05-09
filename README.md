# backend-infra

BridgeWork 운영 공통 인프라(Nginx) 전용 레포입니다.

## 운영 구조
- EC2 인스턴스 1대에서 `backend`(Java Spring)와 `aiserver`(FastAPI)를 함께 운영
- 두 서비스는 동일 인스턴스 내에서 각각 별도의 Docker 컨테이너로 분리 실행
- Nginx는 공통 진입점으로 동작하며 각 서비스 컨테이너로 라우팅

## 역할
- `backend`, `aiserver` 레포와 분리된 Nginx 라우팅/업스트림 운영
- EC2 반영 스크립트 관리
- 공통 인프라 CI/CD 관리

## 디렉터리
- `deploy/nginx/bridgework.conf`
- `deploy/nginx/bridgework-upstream.inc`
- `deploy/nginx/fastapi-upstream.inc`
- `deploy/setup_nginx.sh`
- `deploy/spring_blue_green_switch.sh`
- `deploy/fastapi_blue_green_switch.sh`
- `deploy/NGINX.md`
- `monitoring/docker-compose.monitoring.yml`
- `monitoring/prometheus/*`
- `monitoring/loki/*`
- `monitoring/alloy/*`
- `monitoring/grafana/provisioning/*`

## 모니터링 스택 (Prometheus / Grafana / Loki / Alloy)
- 실행 위치: EC2 `~/bridgework-infra/monitoring`
- 실행 명령: `docker compose -f docker-compose.monitoring.yml up -d`
- 기본 포트:
  - Prometheus: `9090`
  - Grafana: `3000`
  - Loki: `3100`
  - Alloy UI: `12345`

### 필수 환경변수
- `INFRA_ALERT_DISCORD_WEBHOOK_URL` (Grafana 인프라 알림 전용)
- `GRAFANA_ADMIN_USER` (선택, 기본 `admin`)
- `GRAFANA_ADMIN_PASSWORD` (선택, 기본 `admin`)

### Discord 웹훅 분리 규칙
- Spring 앱 알림: `SPRING_BOT_DISCORD_WEBHOOK_URL`
- 인프라/Grafana 알림: `INFRA_ALERT_DISCORD_WEBHOOK_URL`

## CI/CD
- 워크플로우: `.github/workflows/cicd-nginx-ec2.yml`
- 트리거: `main` push(`deploy/**` 변경 시) 또는 수동 실행
- 동작:
  1. 인프라 파일을 EC2 `~/bridgework-infra/deploy`로 업로드
  2. `setup_nginx.sh` 실행
  3. `nginx -t` 검증 후 reload

## GitHub Secrets
- `EC2_HOST`
- `EC2_PORT`
- `EC2_USER`
- `EC2_SSH_PRIVATE_KEY`

## 연동 규칙
- 앱 레포는 자체 배포만 담당하고, 트래픽 전환은 이 레포의 스크립트를 호출
  - Spring: `~/bridgework-infra/deploy/spring_blue_green_switch.sh`
  - FastAPI: `~/bridgework-infra/deploy/fastapi_blue_green_switch.sh`
