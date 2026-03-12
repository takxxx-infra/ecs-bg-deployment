# ##################################################
# Locals
# ##################################################
locals {
  vpce_interfaces = {
    ecr-api = {
      service_name = "com.amazonaws.${local.region}.ecr.api"
    }
    ecr-dkr = {
      service_name = "com.amazonaws.${local.region}.ecr.dkr"
    }
    logs = {
      service_name = "com.amazonaws.${local.region}.logs"
    }
  }
}

# ##################################################
# VPC Endpoint
# ##################################################
resource "aws_vpc_endpoint" "interface" {
  for_each           = local.vpce_interfaces
  vpc_id             = aws_vpc.main.id
  service_name       = each.value.service_name
  vpc_endpoint_type  = "Interface"
  security_group_ids = [aws_security_group.vpce.id]
  subnet_ids = [
    aws_subnet.this["private-a"].id,
    aws_subnet.this["private-c"].id
  ]
  private_dns_enabled = true

  tags = {
    Name = "${local.project_name}-${each.key}"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${local.region}.s3"
  route_table_ids = [
    aws_route_table.private.id
  ]

  tags = {
    Name = "${local.project_name}-s3"
  }
}
