# ##################################################
# Locals
# ##################################################
locals {
  subnets = {
    public-a = {
      cidr = "10.0.0.0/24"
      az   = local.az.a
    }
    public-c = {
      cidr = "10.0.1.0/24"
      az   = local.az.c
    }
    private-a = {
      cidr = "10.0.2.0/24"
      az   = local.az.a
    }
    private-c = {
      cidr = "10.0.3.0/24"
      az   = local.az.c
    }
  }
}

# ##################################################
# Subnets
# ##################################################
resource "aws_subnet" "this" {
  for_each                = local.subnets
  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.value.az
  cidr_block              = each.value.cidr
  map_public_ip_on_launch = strcontains(each.key, "public")
  tags = {
    Name = "${local.project_name}-${each.key}"
  }
}
