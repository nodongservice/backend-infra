# BridgeWork Backend Infrastructure

BridgeWork API의 공통 진입점, Spring·FastAPI Blue/Green 트래픽 전환, 모니터링·로그·알림, 기존 AWS 자원의 Terraform 전환 기반을 관리합니다.

애플리케이션 저장소는 컨테이너 이미지 빌드와 비활성 슬롯 기동을 담당하고, 이 저장소는 Nginx 업스트림을 안전하게 전환해 배포 책임을 분리합니다.

<p align="center">
  <img src="https://raw.githubusercontent.com/nodongservice/.github/main/images_new/system_architect.png" alt="BridgeWork 운영 아키텍처와 배포 및 모니터링 구성" width="100%" />
</p>

## 운영 구조

```text
Internet
  -> HTTPS / Nginx on EC2
       ├─ Spring Blue  :18080
       ├─ Spring Green :18081
       ├─ FastAPI Blue :19000
       └─ FastAPI Green:19001

Application data
  ├─ AWS RDS PostgreSQL + PostGIS
  └─ Redis container

Observability
  ├─ Prometheus -> Grafana
  └─ Alloy -> Loki -> Grafana -> Discord
```

- 운영 EC2 1대에서 Spring Backend와 FastAPI AI/GIS Service를 별도 Docker 컨테이너로 실행합니다.
- `api.bridgework.cloud`의 HTTPS 종단과 API·문서 라우팅은 Nginx가 담당합니다.
- 앱 저장소의 GitHub Actions가 GHCR 이미지를 게시하고 비활성 슬롯을 기동한 뒤 이 저장소의 전환 스크립트를 호출합니다.
- Prometheus·Grafana·Loki·Alloy가 메트릭, 로그, 대시보드와 Discord 알림을 담당합니다.

## 인프라 관리 원칙

- 기존 AWS 운영 자원은 Terraform import-first 방식으로 점진적으로 관리한다.
- Terraform 원격 state는 암호화, 버전 관리, public access 차단 및 lockfile을 적용한 S3 버킷에 저장한다.
- 운영 자원 import 전에는 read-only 인벤토리만 실행하며, replace 또는 destroy 계획은 적용하지 않는다.
- Kubernetes는 현재 서비스 규모와 운영 지표를 기준으로 보류한다. 다중 replica와 자동 확장이 필요해지면 ECS/Fargate와 EKS를 함께 재검토한다.

상세 결정과 도입 단계:

- [Kubernetes 및 Terraform 도입 검토](docs/terraform-kubernetes-review.md)
- [Terraform 운영 가이드](terraform/README.md)

현재 Terraform은 기반 구성과 read-only 운영 인벤토리 단계입니다.

- `terraform/bootstrap`: 암호화·버전 관리·public access 차단·lockfile을 적용한 원격 state S3 버킷
- `terraform/environments/prod`: AWS 기본 태그와 운영 자원 data source 인벤토리
- `imports.tf.example`: 기존 자원을 선언·import할 때 사용할 안전한 예시
- PR과 `main` 변경 시 Terraform 1.15.8 기준 `fmt`, backend 없는 `init`, `validate` 수행

## 디렉터리

| 경로 | 역할 |
| --- | --- |
| `deploy/nginx/` | 운영 server block과 Spring·FastAPI upstream 파일 |
| `deploy/setup_nginx.sh` | 설정 배치, 인증서 확인, `nginx -t`, reload |
| `deploy/*_blue_green_switch.sh` | 새 슬롯 검증과 원자적 upstream 전환 |
| `monitoring/` | Prometheus, Grafana, Loki, Alloy 구성과 Compose |
| `terraform/bootstrap/` | Terraform 원격 state 기반 |
| `terraform/environments/prod/` | 운영 AWS 자원 인벤토리와 점진적 import 대상 |
| `docs/` | Terraform·Kubernetes 도입 판단과 운영 안전 규칙 |

## 팀

| 이름 | 담당 |
| --- | --- |
| 장혜진 | 기획 |
| 김수인 | 디자인 |
| 최성현 | 백엔드 및 인프라 |
| 박민정 | 프론트 및 AI 개발 |

## Nginx와 Blue/Green 배포

- HTTP 요청은 정규 운영 도메인의 HTTPS로 리다이렉트합니다.
- Spring API는 `/api/v1/*`, 문서는 `/api/java/*`로 제공합니다.
- FastAPI 문서·운영 확인 경로는 `/api/py/*`로 분리합니다.
- 인증·프로필 응답에는 `Cache-Control: no-store`를 적용합니다.
- 장시간 OCR·추천·동기화 요청에는 경로별 timeout을 적용합니다.
- 전환 스크립트는 새 컨테이너 health check를 통과한 뒤 upstream 파일을 바꾸고 `nginx -t` 성공 시에만 reload합니다.

앱 저장소는 자체 배포 후 아래 스크립트를 호출합니다.

- Spring: `~/bridgework-infra/deploy/spring_blue_green_switch.sh`
- FastAPI: `~/bridgework-infra/deploy/fastapi_blue_green_switch.sh`

## 모니터링 스택 (Prometheus / Grafana / Loki / Alloy)

<p align="center">
  <img src="https://raw.githubusercontent.com/nodongservice/.github/main/images_new/dataflow_1.png" alt="BridgeWork 모니터링 fallback 정기 동기화 기반 운영 안정화 구조" width="100%" />
</p>

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
- Terraform 검증: `.github/workflows/terraform-validate.yml`
  - 트리거: Terraform 관련 PR·`main` push 또는 수동 실행
  - `bootstrap`, `environments/prod`를 matrix로 검증

## GitHub Secrets
- `EC2_HOST`
- `EC2_PORT`
- `EC2_USER`
- `EC2_SSH_PRIVATE_KEY`
- `INFRA_ALERT_DISCORD_WEBHOOK_URL` (모니터링 배포 필수)
- `GRAFANA_PUBLIC_URL` (모니터링 배포 필수, 예: `https://api.bridgework.cloud/grafana/`)
- `GRAFANA_ADMIN_USER` (선택, 미설정 시 `admin`)
- `GRAFANA_ADMIN_PASSWORD` (선택, 미설정 시 `admin`)

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
