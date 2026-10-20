variable "prefix" {
  type        = string
  description = "Prefix for resource names"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "db_subnet_ids" {
  type = list(string)
}

variable "db_port" {
  type        = number
  description = "Port for the database"
  default     = 5432
}

variable "app_sg" {
  type        = string
  description = "App security group ID"
}

variable "environment" {
  type        = string
  description = "Environment name (e.g. dev, prod) — applied as the Environment tag"
}

variable "db_instance_class" {
  type        = string
  description = "RDS instance class for the database"
  default     = "db.t3.micro"
}