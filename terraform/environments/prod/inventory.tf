locals {
  common_tags = merge(
    {
      Project     = "bridgework"
      Environment = "prod"
      ManagedBy   = "terraform"
      Repository  = "nodongservice/backend-infra"
    },
    var.additional_tags
  )
}

data "aws_caller_identity" "current" {}

data "aws_vpc" "production" {
  id = var.vpc_id
}

data "aws_instance" "application" {
  instance_id = var.ec2_instance_id
}

data "aws_subnet" "application" {
  id = data.aws_instance.application.subnet_id
}

data "aws_db_instance" "production" {
  db_instance_identifier = var.rds_instance_identifier
}

data "aws_route53_zone" "public" {
  zone_id      = var.route53_zone_id
  private_zone = false
}

check "application_instance_is_in_production_vpc" {
  assert {
    condition     = data.aws_subnet.application.vpc_id == data.aws_vpc.production.id
    error_message = "The configured EC2 instance is not in the configured production VPC."
  }
}
