variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Name prefix applied to all resources via tags"
  type        = string
  default     = "bastion-host"
}

variable "instance_type" {
  description = "EC2 instance type for both bastion and private server (t3.micro is free-tier eligible on accounts created after 2021)"
  type        = string
  default     = "t3.micro"
}

variable "allowed_cidr" {
  description = "Your public IP in CIDR notation (e.g. 203.0.113.5/32). Only this IP can reach the bastion on port 22. Never use 0.0.0.0/0."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.allowed_cidr)) && !endswith(var.allowed_cidr, "/0")
    error_message = "allowed_cidr must be a valid CIDR block and must not be 0.0.0.0/0 or ::/0."
  }
}

variable "bastion_public_key" {
  description = "Contents of the Ed25519 public key used to access the bastion host (e.g. the output of: cat ~/.ssh/bastion_key.pub)"
  type        = string
  sensitive   = true
}

variable "private_server_public_key" {
  description = "Contents of the Ed25519 public key used to access the private server (e.g. the output of: cat ~/.ssh/private_server_key.pub)"
  type        = string
  sensitive   = true
}
