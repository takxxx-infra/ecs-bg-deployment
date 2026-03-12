# ##################################################
# Public
# ##################################################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.project_name}-public"
  }
}

resource "aws_route_table_association" "public" {
  for_each = {
    public-ingress-a = aws_subnet.this["public-a"]
    public-ingress-c = aws_subnet.this["public-c"]
  }
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# ##################################################
# App
# ##################################################
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.project_name}-private"
  }
}

resource "aws_route_table_association" "private" {
  for_each = {
    private-app-a = aws_subnet.this["private-a"]
    private-app-c = aws_subnet.this["private-c"]
  }
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
