# BridgeWork Monitoring Stack

Prometheus, Grafana, Loki, Alloy 기반 관측 스택입니다.

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

선택 Secret:
- `GRAFANA_ADMIN_USER`
- `GRAFANA_ADMIN_PASSWORD`
- `GRAFANA_PUBLIC_URL` (예: `https://api.bridgework.cloud/grafana`)

## 2) 수집 대상

- Spring metrics: `http://host.docker.internal/api/java/actuator/prometheus`
- FastAPI metrics: `http://host.docker.internal/api/py/metrics`
- Docker logs: `bridgework-backend-*`, `bridgework-aiserver-*` 컨테이너를 Alloy가 Loki로 전송

## 3) Discord 웹훅 분리

- Spring 앱 봇: `SPRING_BOT_DISCORD_WEBHOOK_URL`
- 인프라 알림(Grafana): `INFRA_ALERT_DISCORD_WEBHOOK_URL`

## 4) 기본 접속

- Prometheus: `http://<SERVER_IP>:9090`
- Grafana: `http://<SERVER_IP>:3000`
- Loki health: `http://<SERVER_IP>:3100/ready`
- Alloy UI: `http://<SERVER_IP>:12345`

## 5) 기본 알림 정책

- Grafana provisioning으로 `infra-discord` contact point가 생성됩니다.
- Grafana provisioning으로 `Spring Backend Down`, `FastAPI Down` 룰이 자동 등록됩니다.
- 운영 환경에서는 임계값/지속시간(`for`)을 트래픽 패턴에 맞춰 추가 튜닝하세요.
