# Kubernetes 및 Terraform 도입 검토

## 결정

- Terraform은 우선 도입한다.
- Kubernetes는 현재 도입하지 않는다.
- 기존 운영 자원은 새로 생성하지 않고, 실제 설정을 조회한 뒤 import-first 방식으로 Terraform 상태에 편입한다.
- AWS 자격 증명과 운영 자원 식별자가 확인되기 전에는 운영 스택에 `terraform apply`를 실행하지 않는다.

## 현재 운영 구조

- 프론트엔드는 Vercel에서 운영한다.
- Spring Backend와 FastAPI AI/GIS Server는 EC2 한 대의 Docker 컨테이너로 운영한다.
- 호스트 Nginx가 HTTPS를 종단하고 Blue/Green 슬롯으로 트래픽을 전환한다.
- PostgreSQL/PostGIS는 RDS를 사용한다.
- Redis는 EC2의 Docker 볼륨에 상태를 저장한다.
- Prometheus, Grafana, Loki, Alloy도 같은 EC2에서 Docker Compose로 운영한다.
- GitHub Actions가 EC2에 SSH로 접속해 설정과 배포 스크립트를 반영한다.

## 문제 정의

### 재현성과 변경 통제

저장소에는 AWS 네트워크, 보안 그룹, EC2, RDS, IAM, DNS 구성을 재현할 선언적 설정이 없었다. EC2에는 Docker, Nginx, curl 설치와 배포 계정 권한 설정이 선행되어야 한다. 서버 장애나 교체 시 저장소만으로 동일한 환경을 복구하기 어렵다.

### 단일 장애 지점

애플리케이션, Redis, Nginx, 관측 스택이 하나의 EC2에 집중되어 있다. RDS는 외부 관리형 서비스지만 EC2 장애 시 API, 인증 세션, 추천 작업 상태, 로그 및 대시보드가 동시에 영향을 받을 수 있다.

### 확장 판단에 필요한 지표 부족

현재 알림은 서비스 응답 여부와 Spring 5xx 비율 중심이다. 다음 정보가 없어 Kubernetes나 자동 확장의 필요성을 정량적으로 판단하기 어렵다.

- EC2 및 컨테이너 CPU, 메모리, 디스크 포화도
- API p95/p99 지연시간과 처리량
- Spring 비동기 executor의 active thread 및 queue 사용량
- FastAPI OCR 작업의 CPU, 메모리, 처리시간
- Redis 메모리, 지연시간, eviction 및 영속성 상태
- 목표 가용성, 복구시간(RTO), 데이터 복구시점(RPO)

## Terraform 평가

Terraform은 현재 배포 방식을 교체하지 않고도 다음 문제를 해결할 수 있다.

- AWS 자원과 보안 설정의 코드 리뷰 및 변경 이력
- 동일 환경 재현과 장애 복구 절차 표준화
- 운영 자원 drift 확인
- 신규 환경을 만들 때 수동 설정 누락 방지
- 최소 권한 IAM과 네트워크 접근 정책의 명시화

### 1차 관리 후보

1. VPC, subnet, route table, internet/NAT gateway
2. security group
3. EC2, Elastic IP, IAM instance profile
4. RDS subnet/parameter group 및 RDS 인스턴스
5. Route 53 레코드
6. CloudWatch alarm과 백업 설정
7. Redis를 외부화할 경우 ElastiCache

운영 자원의 실제 속성을 확인하지 않고 위 자원을 선언하면 교체나 중복 생성이 발생할 수 있다. 따라서 이 변경에서는 원격 상태 기반과 read-only 운영 인벤토리를 먼저 추가하고, 각 자원은 확인 후 한 개씩 import한다.

## Kubernetes 평가

### 기대 효과

- 여러 노드에 걸친 replica 배치와 자동 복구
- Deployment와 Service를 통한 표준 롤링 배포
- CPU/메모리 또는 사용자 정의 지표 기반 자동 확장
- workload별 자원 요청과 제한

### 현재 도입을 보류하는 이유

- 운영 애플리케이션 workload가 Spring과 FastAPI 두 종류로 작다.
- 이미 readiness 확인과 Nginx Blue/Green 전환이 구현되어 있어 배포 기능의 상당 부분이 중복된다.
- Redis와 관측 데이터가 호스트 로컬 볼륨에 있어 Kubernetes만 도입해도 고가용성이 확보되지 않는다.
- 추천과 동기화 작업은 프로세스 내부 executor에서 실행된다. Pod 종료 시 실행 중인 작업을 다른 Pod가 이어받는 내구성 있는 작업 큐가 없다.
- HPA 기준을 정할 CPU, 메모리, 지연시간 및 queue 포화도 지표가 부족하다.
- 클러스터, ingress, 인증서, secret, 네트워크, 저장소, 관측 스택 운영 부담이 서비스 규모에 비해 크다.

## Kubernetes 재검토 조건

다음 조건 중 하나 이상이 운영 지표로 확인될 때 ECS/Fargate와 EKS를 함께 비교한다.

- 단일 EC2 용량 부족이 반복되고 수직 확장의 비용 또는 한계가 명확하다.
- 호스트 장애에 대한 목표 복구시간을 현재 방식으로 충족할 수 없다.
- Spring 또는 FastAPI replica를 독립적으로 여러 개 유지해야 한다.
- 서비스와 배포 팀이 늘어나 workload 스케줄링 표준화가 필요하다.
- 비동기 작업을 내구성 있는 queue/worker 구조로 분리했다.
- Redis와 관측 데이터가 관리형 또는 외부 영속 저장소로 이전되었다.

AWS 중심의 소수 컨테이너라면 EKS 결정 전에 ECS/Fargate를 비교한다.

## 단계별 도입 계획

### 0단계: 기반 구성

- 암호화, 버전 관리, public access 차단을 적용한 S3 상태 버킷을 준비한다.
- S3 lockfile로 동시 실행을 차단한다.
- PR에서 `terraform fmt`, `init -backend=false`, `validate`를 실행한다.

### 1단계: 운영 인벤토리

- AWS 계정과 region을 확인한다.
- VPC, EC2, RDS, Route 53 zone 식별자를 변수로 입력한다.
- read-only `terraform plan`으로 조회 권한과 대상 일치 여부를 확인한다.

### 2단계: 기존 자원 import

- 한 번에 한 자원만 import한다.
- 실제 AWS 속성과 동일한 resource 구성을 작성한다.
- import 직후 `terraform plan`이 변경 없음을 보여야 다음 자원으로 진행한다.
- RDS, 상태 버킷 등 데이터 자원에는 삭제 방지를 적용한다.
- 교체 또는 삭제 계획이 나타나면 apply하지 않고 원인을 먼저 수정한다.

### 3단계: 운영 적용

- Pull Request에서 speculative plan을 생성한다.
- main 반영 후 보호된 GitHub Environment의 승인으로만 apply한다.
- 장기 access key 대신 GitHub Actions OIDC와 최소 권한 IAM Role을 사용한다.
- 애플리케이션 비밀번호와 API key는 Terraform 변수 및 state에 넣지 않는다.

### 4단계: 신뢰성 개선

- Redis 관리형 이전 또는 검증된 백업·복구 절차를 마련한다.
- host/container 자원과 비동기 queue 지표를 추가한다.
- 배포 종료 유예와 실행 중 작업 처리 정책을 검증한다.
- 실제 SLO와 비용을 근거로 ECS 또는 EKS 도입 여부를 다시 결정한다.

## 운영 안전 규칙

- `terraform apply -auto-approve`를 운영 자동화에 사용하지 않는다.
- 저장소에 `.tfstate`, `.tfvars`, plan 파일, credential을 커밋하지 않는다.
- 운영 resource import가 끝날 때까지 생성 목적의 resource를 임의로 추가하지 않는다.
- `terraform plan`의 replace 또는 destroy 항목은 담당자 승인을 받는다.
- RDS와 상태 저장소 변경 전에는 복구 가능한 백업을 확인한다.
