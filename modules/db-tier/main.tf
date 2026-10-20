resource "aws_security_group" "db_sg" {
  name        = "${var.prefix}-db-sg"
  description = "Allow traffic from the app tier"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "${var.prefix}-db-sg"
    Environment = var.environment
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_ingress_rule" {
  security_group_id            = aws_security_group.db_sg.id
  referenced_security_group_id = var.app_sg

  ip_protocol = "tcp"
  from_port   = var.db_port
  to_port     = var.db_port
}

resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "${var.prefix}-db-subnet-group"
  subnet_ids = var.db_subnet_ids

  tags = {
    Name        = "${var.prefix}-db-subnet-group"
    Environment = var.environment
  }
}

resource "aws_db_instance" "db_instance" {
  allocated_storage    = 20
  identifier           = "${var.prefix}-db-instance"
  db_name              = "trailmark"
  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.id
  engine               = "postgres"
  engine_version       = "14"
  instance_class       = var.db_instance_class
  port                 = var.db_port
  username             = "postgres"
  # RDS generates the master password and keeps it in Secrets Manager,
  # so it never passes through Terraform or its state.
  manage_master_user_password = true
  vpc_security_group_ids      = [aws_security_group.db_sg.id]
  publicly_accessible         = false
  multi_az                    = false
  skip_final_snapshot         = true

  tags = {
    Name        = "${var.prefix}-db-instance"
    Environment = var.environment
  }
}
