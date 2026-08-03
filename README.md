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
  ├─ Node Exporter -> Prometheus -> Grafana
  └─ Alloy -> Loki -> Grafana -> Discord
```

- 운영 EC2 1대에서 Spring Backend와 FastAPI AI/GIS Service를 별도 Docker 컨테이너로 실행합니다.
- `api.bridgework.cloud`의 HTTPS 종단과 API·문서 라우팅은 Nginx가 담당합니다.
- 앱 저장소의 GitHub Actions가 GHCR 이미지를 게시하고 비활성 슬롯을 기동한 뒤 이 저장소의 전환 스크립트를 호출합니다.
- Node Exporter·Prometheus·Grafana·Loki·Alloy가 호스트 메트릭, 로그, 대시보드와 Discord 알림을 담당합니다.

## 팀

| 이름 | 담당 |
| --- | --- |
| 장혜진 | 기획 |
| 김수인 | 디자인 |
| 최성현 | 백엔드 및 인프라 |
| 박민정 | 프론트 및 AI 개발 |

## 모니터링 스택 (Node Exporter / Prometheus / Grafana / Loki / Alloy)

<p align="center">
  <img src="https://raw.githubusercontent.com/nodongservice/.github/main/images_new/dataflow_1.png" alt="BridgeWork 모니터링 fallback 정기 동기화 기반 운영 안정화 구조" width="100%" />
</p>

- 호스트 루프백 전용 포트:
  - Prometheus: `9090`
  - Grafana: `3000`
  - Loki: `3100`
  - Alloy UI: `12345`
- Grafana는 Nginx HTTPS 경로로만 공개하고 Prometheus, Loki, Alloy 관리 포트는 외부에 직접 노출하지 않습니다.
- 모든 모니터링 컨테이너는 Docker `local` 로그 드라이버로 `20MB × 3개`까지만 보관합니다.
- EC2 루트 디스크 가용 공간이 `20%` 미만이면 경고, `10%` 미만이면 긴급 알림을 전송합니다.
- Loki Compactor는 로그 데이터를 14일 보관 후 삭제합니다.
