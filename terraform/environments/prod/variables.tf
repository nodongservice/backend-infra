variable "aws_region" {
  description = "AWS region containing the BridgeWork production resources."
  type        = string
  default     = "ap-northeast-2"

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name."
  }
}

variable "vpc_id" {
  description = "Existing production VPC ID. This stack only reads it until import is reviewed."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must look like vpc- followed by hexadecimal characters."
  }
}

variable "ec2_instance_id" {
  description = "Existing application EC2 instance ID. This stack only reads it until import is reviewed."
  type        = string

  validation {
    condition     = can(regex("^i-[0-9a-f]+$", var.ec2_instance_id))
    error_message = "ec2_instance_id must look like i- followed by hexadecimal characters."
  }
}

variable "rds_instance_identifier" {
  description = "Existing production RDS DB instance identifier."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.rds_instance_identifier))
    error_message = "rds_instance_identifier must be a valid RDS DB instance identifier."
  }
}

variable "route53_zone_id" {
  description = "Existing public Route 53 hosted zone ID."
  type        = string

  validation {
    condition     = can(regex("^Z[A-Z0-9]+$", var.route53_zone_id))
    error_message = "route53_zone_id must be a valid Route 53 hosted zone ID."
  }
}

variable "additional_tags" {
  description = "Additional default tags for resources added after import."
  type        = map(string)
  default     = {}
}
