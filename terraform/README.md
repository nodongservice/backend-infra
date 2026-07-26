# BridgeWork Terraform

이 디렉터리는 기존 AWS 운영 자원을 안전하게 Terraform 관리로 전환하기 위한 기반입니다.

## 구성

```text
terraform/
├── bootstrap/          # 원격 state용 S3 버킷
└── environments/
    └── prod/           # 운영 자원 read-only 인벤토리와 향후 import 대상
```

현재 `prod` 구성은 운영 자원을 생성하거나 변경하지 않고 기존 VPC, EC2, RDS, Route 53 zone을 조회합니다. 실제 운영 resource 정의는 AWS 설정과 일치하는지 확인한 후 import와 함께 추가합니다.

## 사전 조건

- Terraform 1.15.8
- 유효한 AWS 자격 증명
- 대상 AWS 계정과 `ap-northeast-2` region 확인
- 운영 VPC, EC2 instance ID, RDS identifier, Route 53 hosted zone ID

자격 증명 확인:

```bash
aws sts get-caller-identity
```

반환된 account와 ARN이 BridgeWork 운영 계정인지 반드시 확인합니다.

## 1. 원격 state 버킷 준비

버킷 이름은 전 세계에서 고유해야 합니다.

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars의 state_bucket_name을 운영용 고유 이름으로 변경

terraform init
terraform plan -out=bootstrap.tfplan
terraform apply bootstrap.tfplan
```

버킷에는 다음 보호가 적용됩니다.

- versioning
- server-side encryption
- public access 차단
- TLS가 아닌 요청 거부
- Terraform lifecycle 삭제 방지

Bootstrap state 파일도 저장소에 커밋하지 않습니다. 버킷 생성 후 제한된 운영 저장소에 보관하고, 복구 절차에 포함합니다.

## 2. 운영 인벤토리 초기화

```bash
cd ../environments/prod
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
```

두 파일의 예시 값을 실제 값으로 변경한 후 실행합니다.

```bash
terraform init -backend-config=backend.hcl
terraform plan
```

이 단계의 plan에는 data source 조회만 존재해야 하며 생성, 변경, 삭제가 없어야 합니다.

## 3. 기존 자원 import

운영 자원은 다음 순서로 한 개씩 편입합니다.

1. VPC와 subnet
2. route table과 gateway
3. security group
4. IAM role과 instance profile
5. EC2와 Elastic IP
6. RDS 관련 자원
7. Route 53 record
8. CloudWatch alarm과 백업 정책

각 자원에 대해:

1. 실제 AWS 속성을 조회합니다.
2. 해당 속성과 일치하는 `resource` block을 작성합니다.
3. `imports.tf.example` 형식으로 임시 import block을 만듭니다.
4. `terraform plan`으로 import 결과를 확인합니다.
5. 변경이 없는 경우에만 apply하여 state에 편입합니다.
6. import block을 제거하고 다시 plan합니다.

교체 또는 삭제가 계획되면 apply하지 않습니다. resource 정의가 실제 설정과 다른 원인을 먼저 해결합니다.

## CI

`.github/workflows/terraform-validate.yml`은 AWS credential 없이 다음을 검사합니다.

- `terraform fmt -check -recursive`
- `terraform init -backend=false`
- `terraform validate`

운영 plan/apply workflow는 기존 자원 import와 GitHub Actions OIDC 역할 준비가 완료된 후 추가합니다.

## Secret 정책

- AWS access key, database password, API key를 `.tf`, `.tfvars`, backend 설정에 저장하지 않습니다.
- Terraform backend와 provider 인증은 환경 변수, AWS profile 또는 GitHub Actions OIDC를 사용합니다.
- Terraform state에 민감 값이 들어갈 수 있으므로 버킷 접근 권한을 운영 담당자로 제한합니다.
