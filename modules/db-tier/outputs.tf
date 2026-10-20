output "db_endpoint" {
  value       = aws_db_instance.db_instance.address
  description = "RDS instance hostname"
}

output "db_port" {
  value       = aws_db_instance.db_instance.port
  description = "RDS instance port"
}

output "db_name" {
  value       = aws_db_instance.db_instance.db_name
  description = "Initial database name"
}

output "secret_arn" {
  value       = aws_db_instance.db_instance.master_user_secret[0].secret_arn
  description = "ARN of the RDS-managed Secrets Manager secret holding the master username and password"
}
