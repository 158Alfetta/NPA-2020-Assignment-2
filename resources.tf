##################################################################################
# DATA
##################################################################################


data "aws_availability_zones" "available" {}

data "aws_ami" "aws-linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
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

##################################################################################
# RESOURCES - NETWORKING
##################################################################################


resource "aws_vpc" "vpc" {
    cidr_block = var.network_address_space[terraform.workspace]
    enable_dns_hostnames = true

    tags ={
        Name = "NPA21-vpc-${local.env_name}"
    }
}

resource "aws_subnet" "subnet" {
    count = var.subnet_count[terraform.workspace]
    vpc_id = aws_vpc.vpc.id
    cidr_block = cidrsubnet(var.network_address_space[terraform.workspace], var.subnet_size[terraform.workspace], count.index)
    availability_zone = data.aws_availability_zones.available.names[count.index]
    map_public_ip_on_launch = true
    tags ={
        Name = "NPA21-subnet-${local.env_name}-${count.index + 1}"
    }
}


resource "aws_internet_gateway" "internet_gw" {
    vpc_id = aws_vpc.vpc.id
    tags ={
        Name = "NPA21-InternetGateway-${local.env_name}"
    }
}

resource "aws_route_table" "routetable" {
    vpc_id = aws_vpc.vpc.id
        route {
            cidr_block = "0.0.0.0/0"
            gateway_id = aws_internet_gateway.internet_gw.id
        }
    tags = {
        Name = "NPA-RouteTable-${local.env_name}"
    }
}

resource "aws_route_table_association" "rt-subnet" {
  count = var.subnet_count[terraform.workspace]
  subnet_id = aws_subnet.subnet[count.index].id
  route_table_id = aws_route_table.routetable.id
}

##################################################################################
# RESOURCES - SECURITY GROUP
##################################################################################


resource "aws_security_group" "lb-sg" {
    name = "NPA21-lb-sg-${local.env_name}"
    vpc_id = aws_vpc.vpc.id

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]

    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
      Name = "NPA21-lb-sg-${local.env_name}"
    }
}

resource "aws_security_group" "allow_ssh_web" {
  name        = "allow_ssh_web"
  description = "Allow ssh and web access"
  vpc_id      = aws_vpc.vpc.id

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
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "NPA21-allow_ssh_web-${local.env_name}"
  }
}

##################################################################################
# RESOURCES - INSTANCES
##################################################################################


resource "aws_instance" "modelServer" {
  ami                    = data.aws_ami.aws-linux.id
  instance_type          = var.instance_size[terraform.workspace]
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.allow_ssh_web.id]
  subnet_id = aws_subnet.subnet[0].id

  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ec2-user"
    private_key = file(var.private_key_path)

  }

  provisioner "remote-exec" {
    inline = [
        "sudo yum update -y",
        "sudo yum install git -y",
        "sudo amazon-linux-extras install nginx1 -y",
        "cd /home/ec2-user",
        "git clone https://github.com/enjoy1818/SpaceX-page.git",
        "ls SpaceX-page/space-x/",
        "cd SpaceX-page/space-x/",
        "sudo curl -sL https://rpm.nodesource.com/setup_14.x | sudo bash -",
        "sudo yum install -y nodejs",
        "ls",
        "pwd",
        "npm install",
        "npm add react-infinite-scroll-component",
        "npm run build",
        "sudo \\cp -r ./build/* /usr/share/nginx/html/",
        "sudo service nginx start"
    ]
  }

  tags = {
      Name = "NPA21-modelServer-${local.env_name}"
  }
}

resource "aws_ami_from_instance" "create-ami" {
  name = "create-ami"
  source_instance_id = aws_instance.modelServer.id
  snapshot_without_reboot = true
  
  tags = {
    Name = "modelServer"
  }
}

# Launch Configuration
resource "aws_launch_configuration" "launch-config" {
  name_prefix = "web-"

  image_id = aws_ami_from_instance.create-ami.id
  instance_type = var.instance_size[terraform.workspace]
  security_groups = [aws_security_group.allow_ssh_web.id]
  associate_public_ip_address = true

  user_data = <<-EOF
            #!/bin/bash
            npm install
            npm add react-infinite-scroll-component
            npm run build
            sudo \cp -r ./build/* /usr/share/nginx/html/
            sudo service nginx start
            EOF

  lifecycle {
    create_before_destroy = true
  }
}


# LB Target group

resource "aws_lb_target_group" "server_target_group" {
  name     = "server-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id

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
 resource "aws_elb" "elastic-lb" {
  name = "elastic-lb"

  subnets = aws_subnet.subnet[*].id
  security_groups = [aws_security_group.lb-sg.id]

  listener {
    instance_port       = 80
    instance_protocol   = "http"
    lb_port             = 80
    lb_protocol         = "http"
  }

  tags = {
    Name = "NPA21-elastic-lb-${local.env_name}"
  }
}

# Autoscaling group

resource "aws_autoscaling_group" "create-autoscaling" {
  name = "create-autoscaling"

  min_size             = var.min_size[terraform.workspace]
  desired_capacity     = var.desired_capacity[terraform.workspace]
  max_size             = var.max_size[terraform.workspace]
  health_check_type    = "ELB"

  launch_configuration = aws_launch_configuration.launch-config.name


  vpc_zone_identifier  = aws_subnet.subnet[*].id
  target_group_arns = [aws_lb_target_group.server_target_group.arn]

  lifecycle {
    create_before_destroy = true
  }
    tag {
    key                 = "Name"
    value               = "NPA21-asg-${local.env_name}"
    propagate_at_launch = true
  }
}

# Attach Autoscaling group to LB
resource "aws_autoscaling_attachment" "attach-scalingToLB" {
  autoscaling_group_name = aws_autoscaling_group.create-autoscaling.id
  elb                    = aws_elb.elastic-lb.id
}