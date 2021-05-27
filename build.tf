##################################################################################
# VARIABLES
##################################################################################

variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "private_key_path" {}
variable "key_name" {}
variable "region" {
  default = "us-east-1"
}
variable "VPC_blocky" {
  default = "10.0.0.0/16"
}

variable "Subnet_1" {
  default = "10.0.1.0/24"
}

variable "Subnet_2" {
  default = "10.0.2.0/24"
}

# data

data "aws_availability_zones" "available" {}

data "aws_ami" "aws-linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-hvm*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

##################################################################################
# PROVIDERS
##################################################################################

provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.region
}

# VPC

resource "aws_vpc" "ServerVPC" {
    cidr_block = var.VPC_blocky
    enable_dns_hostnames = true

    tags ={
        Name = "ServerVPC"
    }
}

#Subnet
resource "aws_subnet" "Subnet_1" {
    vpc_id = aws_vpc.ServerVPC.id
    cidr_block = var.Subnet_1
    availability_zone = data.aws_availability_zones.available.names[0]
    map_public_ip_on_launch = true
    tags ={
        Name = "Subnet_1"
    }
}

resource "aws_subnet" "Subnet_2" {
    vpc_id = aws_vpc.ServerVPC.id
    cidr_block = var.Subnet_2
    availability_zone = data.aws_availability_zones.available.names[1]
    map_public_ip_on_launch = true
    tags ={
        Name = "Subnet_2"
    }
}

# Gateway

resource "aws_internet_gateway" "Igw" {
    vpc_id = aws_vpc.ServerVPC.id
    tags ={
        Name = "Internetgw"
    }
}

# Routing Table

resource "aws_route_table" "publicRoute" {
    vpc_id = aws_vpc.ServerVPC.id
        route {
            cidr_block = "0.0.0.0/0"
            gateway_id = aws_internet_gateway.Igw.id
        }
    tags ={
        Name = "publicRoute"
    }
}

# Route Entry

resource "aws_route_table_association" "rt-Subnet_1" {
  subnet_id = aws_subnet.Subnet_1.id
  route_table_id = aws_route_table.publicRoute.id
}

resource "aws_route_table_association" "rt-Subnet_2" {
  subnet_id = aws_subnet.Subnet_2.id
  route_table_id = aws_route_table.publicRoute.id
}

# Security group

resource "aws_security_group" "lb-sg" {
    name = "lb-sg"
    vpc_id = aws_vpc.ServerVPC.id

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_security_group" "allow_ssh_web" {
  name        = "allow_ssh_web"
  description = "Allow ssh and web access"
  vpc_id      = aws_vpc.ServerVPC.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Instance
resource "aws_instance" "Webserver" {
  ami                    = data.aws_ami.aws-linux.id
  instance_type          = "t2.micro"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.allow_ssh_web.id]
  subnet_id = aws_subnet.Subnet_1.id
  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ec2-user"
    private_key = file(var.private_key_path)

  }

  tags ={
      Name = "Server1"
  }
}

# Instance template
resource "aws_ami_from_instance" "Web-ami" {
  name = "web-ami"
  source_instance_id = aws_instance.Webserver.id
  snapshot_without_reboot = true
  
  tags = {
    Name = "Webserver-ami"
  }
}

# Launch Configuration
resource "aws_launch_configuration" "scaleCmd" {
  name_prefix = "web-"

  image_id = aws_ami_from_instance.Web-ami.id
  instance_type = "t2.micro"
  security_groups = [aws_security_group.allow_ssh_web.id]
  associate_public_ip_address = true

  user_data = <<-EOF
            #!/bin/bash
            sudo su
            yum update -y
            yum install git -y
            amazon-linux-extras install nginx1 -y
            cd /home/ec2-user
            git clone https://github.com/enjoy1818/SpaceX-page.git
            cd SpaceX-page/space-x/
            curl -sL https://rpm.nodesource.com/setup_14.x | bash -
            yum install -y nodejs
            npm install 
            npm add react-infinite-scroll-component
            npm run build
            \cp -r ./build/* /usr/share/nginx/html/
            service nginx start
            EOF

  lifecycle {
    create_before_destroy = true
  }
}

# # Load Balancer

# resource "aws_lb" "loadBL" {
#   name               = "loadBalancer"
#   internal           = false
#   load_balancer_type = "application"
#   security_groups    = [aws_security_group.lb-sg.id]
#   subnets            = [aws_subnet.Subnet_1.id, aws_subnet.Subnet_2.id]

#   enable_deletion_protection = false

# }

# resource "aws_lb_listener" "web_listener" {
#   load_balancer_arn = aws_lb.loadBL.arn
#   port              = "80"
#   protocol          = "HTTP"

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.Server_target_group.arn
#   }
# }

# LB Target group

resource "aws_lb_target_group" "Server_target_group" {
  name     = "Server-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.ServerVPC.id

  health_check {
    path = "/"
    port = 80
    protocol = "HTTP"
    matcher = "200"
    interval = 5 
    timeout = 3
    healthy_threshold = 2
    unhealthy_threshold = 2
  }
}

# Load balancer
resource "aws_elb" "loadBL" {
  name = "web-LoadBalancer"

  subnets = [aws_subnet.Subnet_1.id, aws_subnet.Subnet_2.id]
  security_groups = [aws_security_group.lb-sg.id]

  listener {
    instance_port       = 80
    instance_protocol   = "http"
    lb_port             = 80
    lb_protocol         = "http"
  }

  tags = {
    Name = "Weblb"
  }
}

# Autoscaling group
resource "aws_autoscaling_group" "webscale" {
  name = "${aws_launch_configuration.scaleCmd.name}-asg"

  min_size             = 2
  desired_capacity     = 2
  max_size             = 4
  health_check_type    = "ELB"

  launch_configuration = aws_launch_configuration.scaleCmd.name


  vpc_zone_identifier  = [
    aws_subnet.Subnet_1.id,
    aws_subnet.Subnet_2.id
  ]
  target_group_arns = [aws_lb_target_group.Server_target_group.arn]

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "webScale"
    propagate_at_launch = true
  }
}

# # Attach LB to target froup

# resource "aws_lb_target_group_attachment" "attachServer1" {
#   target_group_arn = aws_lb_target_group.Server_target_group.arn
#   target_id        = aws_instance.Server1.id
#   port             = 80
# }

# resource "aws_lb_target_group_attachment" "attachServer2" {
#   target_group_arn = aws_lb_target_group.Server_target_group.arn
#   target_id        = aws_instance.Server2.id
#   port             = 80
# }

# Attach Autoscaling group to LB
resource "aws_autoscaling_attachment" "scalingToLB" {
  autoscaling_group_name = aws_autoscaling_group.webscale.id
  elb                    = aws_elb.loadBL.id
}

# Print

output "aws_lb_public_dns" {
  value = aws_elb.loadBL.dns_name
}