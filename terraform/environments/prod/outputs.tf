output "aws_account_id" {
  description = "AWS account containing the production resources."
  value       = data.aws_caller_identity.current.account_id
}

output "vpc" {
  description = "Read-only summary of the existing production VPC."
  value = {
    id         = data.aws_vpc.production.id
    cidr_block = data.aws_vpc.production.cidr_block
  }
}

output "application_instance" {
  description = "Read-only summary of the existing application EC2 instance."
  value = {
    id                 = data.aws_instance.application.id
    instance_type      = data.aws_instance.application.instance_type
    availability_zone  = data.aws_instance.application.availability_zone
    private_ip         = data.aws_instance.application.private_ip
    vpc_security_group = data.aws_instance.application.security_groups
  }
}

output "database" {
  description = "Read-only summary of the existing RDS instance."
  value = {
    identifier          = data.aws_db_instance.production.db_instance_identifier
    engine              = data.aws_db_instance.production.engine
    engine_version      = data.aws_db_instance.production.engine_version
    instance_class      = data.aws_db_instance.production.db_instance_class
    availability_zone   = data.aws_db_instance.production.availability_zone
    multi_az            = data.aws_db_instance.production.multi_az
    storage_encrypted   = data.aws_db_instance.production.storage_encrypted
    publicly_accessible = data.aws_db_instance.production.publicly_accessible
  }
}

output "public_dns_zone" {
  description = "Read-only summary of the existing Route 53 public hosted zone."
  value = {
    id   = data.aws_route53_zone.public.zone_id
    name = data.aws_route53_zone.public.name
  }
}
