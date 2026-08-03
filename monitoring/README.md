# BridgeWork Monitoring Stack

Prometheus, Node Exporter, Grafana, Loki, Alloy 기반 관측 스택입니다.

## 1) 실행

```bash
cd ~/bridgework-infra/monitoring
cp .env.example .env
# .env에서 비밀번호/웹훅 수정

docker compose --env-file .env -f docker-compose.monitoring.yml up -d
```

GitHub Actions 배포를 사용할 경우 `.env`는 워크플로우가 자동 생성합니다.

필수 Secret:
- `INFRA_ALERT_DISCORD_WEBHOOK_URL`
- `GRAFANA_PUBLIC_URL` (예: `https://api.bridgework.cloud/grafana/`)

선택 Secret:
- `GRAFANA_ADMIN_USER`
- `GRAFANA_ADMIN_PASSWORD`

## 2) 수집 대상

- Spring metrics: `http://host.docker.internal/api/java/actuator/prometheus`
- FastAPI metrics: `http://host.docker.internal/api/py/metrics`
- EC2 host metrics: Node Exporter가 루트 파일시스템을 읽기 전용으로 수집
- Docker logs: `bridgework-backend-*`, `bridgework-aiserver-*` 컨테이너를 Alloy가 Loki로 전송
- Docker 로그: 컨테이너당 `20MB × 3개`로 순환 보관
- Loki 로그 데이터: Compactor가 14일 보관 후 삭제

## 3) Discord 웹훅 분리

- Spring 앱 봇: `SPRING_BOT_DISCORD_WEBHOOK_URL`
- 인프라 알림(Grafana): `INFRA_ALERT_DISCORD_WEBHOOK_URL`

## 4) 기본 접속

- Grafana: `GRAFANA_PUBLIC_URL`의 HTTPS 경로
- Prometheus: 서버 내부 `http://127.0.0.1:9090`
- Loki health: 서버 내부 `http://127.0.0.1:3100/ready`
- Alloy UI: 서버 내부 `http://127.0.0.1:12345`

모니터링 포트는 외부에 직접 공개하지 않으며, 운영 점검 시 SSH 터널을 사용합니다.

## 5) 기본 알림 정책

- Grafana provisioning으로 `infra-discord` contact point가 생성됩니다.
- Grafana provisioning으로 서비스 Down 및 루트 디스크 `20%/10%` 임계치 룰이 자동 등록됩니다.
- 운영 환경에서는 임계값/지속시간(`for`)을 트래픽 패턴에 맞춰 추가 튜닝하세요.
