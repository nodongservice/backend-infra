# backend-infra

BridgeWork 운영 공통 인프라(Nginx + Monitoring) 레포입니다.

## 인프라 관리 원칙

- 기존 AWS 운영 자원은 Terraform import-first 방식으로 점진적으로 관리한다.
- Terraform 원격 state는 암호화, 버전 관리, public access 차단 및 lockfile을 적용한 S3 버킷에 저장한다.
- 운영 자원 import 전에는 read-only 인벤토리만 실행하며, replace 또는 destroy 계획은 적용하지 않는다.
- Kubernetes는 현재 서비스 규모와 운영 지표를 기준으로 보류한다. 다중 replica와 자동 확장이 필요해지면 ECS/Fargate와 EKS를 함께 재검토한다.

상세 결정과 도입 단계:

- [Kubernetes 및 Terraform 도입 검토](docs/terraform-kubernetes-review.md)
- [Terraform 운영 가이드](terraform/README.md)

## 운영 구조
- EC2 인스턴스 1대에서 `backend`(Java Spring)와 `aiserver`(FastAPI)를 함께 운영
- 두 서비스는 동일 인스턴스 내에서 각각 별도의 Docker 컨테이너로 분리 실행
- Nginx는 공통 진입점으로 동작하며 각 서비스 컨테이너로 라우팅

## 역할
- `backend`, `aiserver` 레포와 분리된 Nginx 라우팅/업스트림 운영
- Prometheus/Grafana/Loki/Alloy 모니터링 스택 운영
- EC2 반영 스크립트 관리
- 공통 인프라 CI/CD 관리

## 디렉터리
- `terraform/bootstrap/*`
- `terraform/environments/prod/*`
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
- 실행 명령: `docker compose --env-file .env -f docker-compose.monitoring.yml up -d`
- 기본 포트:
  - Prometheus: `9090`
  - Grafana: `3000`
  - Loki: `3100`
  - Alloy UI: `12345`

### 필수 환경변수
- `INFRA_ALERT_DISCORD_WEBHOOK_URL` (Grafana 인프라 알림 전용)
- `GRAFANA_PUBLIC_URL` (Grafana 알림 링크용 외부 접속 URL)

### 선택 환경변수
- `GRAFANA_ADMIN_USER` (기본 `admin`)
- `GRAFANA_ADMIN_PASSWORD` (기본 `admin`)

### Discord 웹훅 분리 규칙
- Spring 앱 알림: `SPRING_BOT_DISCORD_WEBHOOK_URL`
- 인프라/Grafana 알림: `INFRA_ALERT_DISCORD_WEBHOOK_URL`

## CI/CD
- Nginx 워크플로우: `.github/workflows/cicd-nginx-ec2.yml`
  - 트리거: `main` push(`deploy/**` 변경 시) 또는 수동 실행
  - 동작:
    1. 인프라 파일을 EC2 `~/bridgework-infra/deploy`로 업로드
    2. `setup_nginx.sh` 실행
    3. `nginx -t` 검증 후 reload
- Monitoring 워크플로우: `.github/workflows/cicd-monitoring-ec2.yml`
  - 트리거: `main` push(`monitoring/**` 변경 시) 또는 수동 실행
  - 동작:
    1. 모니터링 파일을 EC2 `~/bridgework-infra/monitoring`로 업로드
    2. GitHub Secrets로 `.env` 생성
    3. `docker compose --env-file .env -f docker-compose.monitoring.yml up -d --remove-orphans` 실행

## GitHub Secrets
- `EC2_HOST`
- `EC2_PORT`
- `EC2_USER`
- `EC2_SSH_PRIVATE_KEY`
- `INFRA_ALERT_DISCORD_WEBHOOK_URL` (모니터링 배포 필수)
- `GRAFANA_PUBLIC_URL` (모니터링 배포 필수, 예: `https://api.bridgework.cloud/grafana/`)
- `GRAFANA_ADMIN_USER` (선택, 미설정 시 `admin`)
- `GRAFANA_ADMIN_PASSWORD` (선택, 미설정 시 `admin`)

## 연동 규칙
- 앱 레포는 자체 배포만 담당하고, 트래픽 전환은 이 레포의 스크립트를 호출
  - Spring: `~/bridgework-infra/deploy/spring_blue_green_switch.sh`
  - FastAPI: `~/bridgework-infra/deploy/fastapi_blue_green_switch.sh`

## 개인정보 보호 운영 기준
- 외부 전송 구간은 Nginx HTTPS 종단과 HSTS로 보호한다.
- 인증/프로필 API 응답은 `Cache-Control: no-store`로 브라우저·프록시 캐시 저장을 제한한다.
- 운영 알림과 로그 수집 경로에는 이메일, 전화번호, 토큰이 그대로 남지 않도록 앱 레벨 마스킹 정책을 함께 유지한다.
- 민감 프로필 접근 권한은 일반 관리자와 분리하고, 접근 이력은 앱 DB의 감사 로그와 운영 점검 절차로 확인한다.

## 개인정보 영향평가 운영 절차
- 아래 변경은 배포 전 영향평가 체크리스트 검토 대상이다.
- 민감정보 신규 수집 또는 자유기술형 장애 정보 저장 범위 확대
- OCR/AI 분석 입력·출력 범위 변경
- 제3자 제공/처리위탁 범위 변경
- 관리자 운영 화면 또는 대리 로그인 기능 변경
- 프로필 저장 구조, 보유 기간, 파기 절차 변경

### 점검 항목
- 수집 최소화와 목적별 분리 저장이 유지되는지 확인
- 저장·전송 구간 암호화 설정과 키 주입 경로를 점검
- 로그/알림/운영 화면 마스킹과 캐시 금지 정책을 확인
- 권한 분리, 접근 이력, 장애 복구 절차를 검토
