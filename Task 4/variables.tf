variable "project" {
  description = "Project name prefix for resources"
  type        = string
  default     = "future20"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "azs" {
  description = "Availability zones to use"
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b"]
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.20.0.0/16"
}

variable "admin_cidr" {
  description = "Your office/home public IP range allowed to SSH to bastion (e.g. 203.0.113.10/32)"
  type        = string
}

variable "ssh_key_name" {
  description = "Existing EC2 key pair name (created manually or via Terraform if you prefer)"
  type        = string
}

variable "bastion_instance_type" {
  description = "Instance type for bastion"
  type        = string
  default     = "t3.micro"
}

variable "data_node_count" {
  description = "Number of private data platform nodes"
  type        = number
  default     = 2
}

variable "data_node_instance_type" {
  description = "Instance type for data platform nodes"
  type        = string
  default     = "t3.large"
}

variable "data_disk_gb" {
  description = "Size of additional data disk attached to each data node (GB)"
  type        = number
  default     = 200
}
