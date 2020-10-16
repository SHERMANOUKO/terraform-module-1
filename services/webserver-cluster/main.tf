# Specify terraform version
terraform {
  required_version = ">= 0.12.26"
}

# Create launch configuration for each EC2 in the ASG

resource "aws_launch_configuration" "example" {
  # Ubuntu Server 18.04 LTS (HVM), SSD Volume Type in us-east-2
  image_id        = "ami-0c55b159cbfafe1f0"
  instance_type   = var.instance_type
  security_groups = [aws_security_group.instance.id]

  user_data = <<-EOF
              #!/bin/bash
              echo "Hello, World" > index.html
              nohup busybox httpd -f -p "${var.server_port}" &
              EOF

  # set create_before_destroy = true always when using ASG
  lifecycle {
    create_before_destroy = true
  }
}

# fetch list of availability zones in current region
data "aws_availability_zones" "all" {}

# Create the ASG (Auto Scaling Group)
resource "aws_autoscaling_group" "example" {
  launch_configuration = aws_launch_configuration.example.id
  availability_zones   = data.aws_availability_zones.all.names

  min_size = var.min_size
  max_size = var.max_size

  load_balancers    = [aws_elb.example.name]
  health_check_type = "ELB"

  tag {
    key                 = "Name"
    value               = var.cluster_name
    propagate_at_launch = true
  }
}

# Create security group for each EC2 in the ASG
resource "aws_security_group" "instance" {
  name = "${var.cluster_name}-instance"

  # Inbound HTTP from anywhere
  ingress {
    from_port   = var.server_port
    to_port     = var.server_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Elastic Load Balancer (ELB) to route traffic
resource "aws_elb" "example" {
  name               = var.cluster_name
  security_groups    = [aws_security_group.elb.id]
  availability_zones = data.aws_availability_zones.all.names

  health_check {
    target              = "HTTP:${var.server_port}/"
    interval            = 30
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  # This adds a listener for incoming HTTP requests.
  listener {
    lb_port           = var.elb_port
    lb_protocol       = "http"
    instance_port     = var.server_port
    instance_protocol = "http"
  }
}

# Security group for ELB. Where traffic comes in and where it can go out to
resource "aws_security_group" "elb" {
  name = "${var.cluster_name}-elb"

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Inbound HTTP from anywhere
  ingress {
    from_port   = var.elb_port
    to_port     = var.elb_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
