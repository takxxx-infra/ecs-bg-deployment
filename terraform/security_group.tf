# ##################################################
# Locals
# ##################################################
locals {
  port = {
    http = {
      alb          = 80
      alb_test     = 20080
      frontend_app = 8080
    }
    https = 443
  }
}

# ##################################################
# Ingress
# ##################################################
resource "aws_security_group" "alb" {
  name        = "${local.project_name}-alb"
  description = "alb"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.project_name}-alb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_ipv4" {
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "tcp"
  from_port         = local.port.http.alb
  to_port           = local.port.http.alb
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "alb_test_ipv4" {
  security_group_id = aws_security_group.alb.id
  ip_protocol       = "tcp"
  from_port         = local.port.http.alb_test
  to_port           = local.port.http.alb_test
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ##################################################
# Frontend App
# ##################################################
resource "aws_security_group" "frontend_app" {
  name   = "frontend-app"
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.project_name}-frontend-app"
  }
}

resource "aws_vpc_security_group_ingress_rule" "frontend_app" {
  security_group_id            = aws_security_group.frontend_app.id
  ip_protocol                  = "tcp"
  from_port                    = local.port.http.frontend_app
  to_port                      = local.port.http.frontend_app
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "frontend" {
  security_group_id = aws_security_group.frontend_app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ##################################################
# VPC Endpoint
# ##################################################
resource "aws_security_group" "vpce" {
  name        = "${local.project_name}-vpce"
  description = "-"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.project_name}-vpce"
  }
}

resource "aws_vpc_security_group_ingress_rule" "vpce" {
  security_group_id            = aws_security_group.vpce.id
  ip_protocol                  = "tcp"
  from_port                    = local.port.https
  to_port                      = local.port.https
  referenced_security_group_id = aws_security_group.frontend_app.id
}

resource "aws_vpc_security_group_egress_rule" "vpce" {
  security_group_id = aws_security_group.vpce.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
