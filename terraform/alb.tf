# ##################################################
# Locals
# ##################################################
locals {
  target_groups = toset([
    "frontapp-blue",
    "frontapp-green"
  ])
}

# ##################################################
# Target Group
# ##################################################
resource "aws_lb_target_group" "this" {
  for_each         = local.target_groups
  name             = "${local.project_name}-${each.key}"
  target_type      = "ip"
  protocol         = "HTTP"
  port             = 8080
  ip_address_type  = "ipv4"
  vpc_id           = aws_vpc.main.id
  protocol_version = "HTTP1"
  health_check {
    protocol            = "HTTP"
    path                = "/healthcheck"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 15
    matcher             = "200"
    enabled             = true
  }
}

# ##################################################
# ALB
# ##################################################
resource "aws_lb" "main" {
  name               = "${local.project_name}-alb"
  load_balancer_type = "application"
  internal           = false
  ip_address_type    = "ipv4"
  subnets = [
    aws_subnet.this["public-a"].id,
    aws_subnet.this["public-c"].id
  ]
  security_groups = [
    aws_security_group.alb.id
  ]
}

# ##################################################
# ALB Listener
# ##################################################
resource "aws_lb_listener" "production" {
  protocol          = "HTTP"
  port              = local.port.http.alb
  load_balancer_arn = aws_lb.main.arn
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener" "test" {
  protocol          = "HTTP"
  port              = local.port.http.alb_test
  load_balancer_arn = aws_lb.main.arn
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

# ##################################################
# ALB Listener Rule
# ##################################################
resource "aws_lb_listener_rule" "production" {
  listener_arn = aws_lb_listener.production.arn
  priority     = 10
  condition {
    path_pattern {
      values = ["/*"]
    }
  }
  action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.this["frontapp-blue"].arn
        weight = 1
      }
      target_group {
        arn    = aws_lb_target_group.this["frontapp-green"].arn
        weight = 0
      }
    }
  }
  lifecycle {
    ignore_changes = [action]
  }
}

resource "aws_lb_listener_rule" "test" {
  listener_arn = aws_lb_listener.test.arn
  priority     = 10
  condition {
    path_pattern {
      values = ["/*"]
    }
  }
  action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.this["frontapp-blue"].arn
        weight = 1
      }
      target_group {
        arn    = aws_lb_target_group.this["frontapp-green"].arn
        weight = 0
      }
    }
  }
  lifecycle {
    ignore_changes = [action]
  }
}
