#Create EC2 for test purpose
resource "aws_instance" "task17-skryvoruchko-test-instance" {
  ami           = "ami-076309742d466ad69"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.task17-skryvoruchko-public-1.id

  # Enable public IP address
  associate_public_ip_address = true

  # Add security group to allow SSH traffic
  vpc_security_group_ids = [
    "${aws_security_group.task17-skryvoruchko-test-instance.id}"
  ]

  # Use existing security key "test-SKryvoruchko-instance"
  key_name = "test-SKryvoruchko-instance"
  tags = {
    Name = "task17-skryvoruchko-test-instance"
  }
}


#LOAD BALANCER
resource "aws_alb" "task17-skryvoruchko-alb" {
  subnets = [
    "${aws_subnet.task17-skryvoruchko-public-1.id}",
    "${aws_subnet.task17-skryvoruchko-public-2.id}"
  ]
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["${aws_security_group.task17-skryvoruchko-lb_security_group.id}"]
}


resource "aws_lb_listener" "task17-skryvoruchko-listener" {
  load_balancer_arn = aws_alb.task17-skryvoruchko-alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    target_group_arn = aws_lb_target_group.task17-skryvoruchko-tg.arn
    type             = "forward"
  }
}

resource "aws_lb_target_group" "task17-skryvoruchko-tg" {
  name     = "task17-skryvoruchko-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.task17-skryvoruchko-vpc.id
}

#AUTOSCALONG GROUP
resource "aws_autoscaling_group" "task17-skryvoruchko-asg" {
  min_size            = 1
  max_size            = 4
  desired_capacity    = 2
  vpc_zone_identifier = ["${aws_subnet.task17-skryvoruchko-private-1.id}", "${aws_subnet.task17-skryvoruchko-private-2.id}"]
  # target_group_arns    = ["{aws_alb.task17-skryvoruchko-alb.arn}"]

  launch_template {
    id      = aws_launch_template.task17-skryvoruchko-lc.id
    version = "$Latest"
  }

  depends_on = [
    aws_alb.task17-skryvoruchko-alb,
    aws_launch_template.task17-skryvoruchko-lc
  ]
}

#SET:Scaling policy: CPU
#       	Threshold: 10%
resource "aws_autoscaling_policy" "task17-skryvoruchko-cpu_scaling_policy" {
  name                      = "cpu_scaling_policy"
  autoscaling_group_name    = aws_autoscaling_group.task17-skryvoruchko-asg.name
  adjustment_type           = "PercentChangeInCapacity"
  policy_type               = "TargetTrackingScaling"
  estimated_instance_warmup = 300
  target_tracking_configuration {
    target_value = 10
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
  }
}


resource "aws_autoscaling_attachment" "task17-skryvoruchko-tg-attachment" {
  autoscaling_group_name = aws_autoscaling_group.task17-skryvoruchko-asg.id
  lb_target_group_arn    = aws_lb_target_group.task17-skryvoruchko-tg.arn
}


#LAUCH TEMPLATE
resource "aws_launch_template" "task17-skryvoruchko-lc" {
  vpc_security_group_ids = [aws_security_group.http-inbound-asg.id]
  user_data = base64encode(<<-EOF
#!/bin/bash

amazon-linux-extras install nginx1 -y
systemctl enable nginx
systemctl start nginx

echo $HOSTNAME > /usr/share/nginx/html/index.html
EOF
  )

  image_id      = "ami-076309742d466ad69"
  instance_type = "t2.micro"
  key_name      = "test-SKryvoruchko-instance" #!!!!!!!!HERE specefied existing on AWS key
  name          = "task17-SKryvoruchko-instance"
  tags = {
    Name = "task17-skryvoruchko-test-ASG-instance"
  }
}



#Security Groups

#SECURITY GROUP Test Instance
resource "aws_security_group" "task17-skryvoruchko-test-instance" {
  name        = "test_instance_group"
  description = "Security group for the test instance"
  vpc_id      = aws_vpc.task17-skryvoruchko-vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "task17-skryvoruchko-test-instance"
  }
}


#SECURITY GROUP LOADBALANCER
resource "aws_security_group" "task17-skryvoruchko-lb_security_group" {
  name        = "lb_security_group"
  description = "Security group for the load balancer"
  vpc_id      = aws_vpc.task17-skryvoruchko-vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "task17-skryvoruchko-lb_security_group"
  }
}


#SECURITY GROUP ASG
resource "aws_security_group" "http-inbound-asg" {
  name        = "http-inbound-lb"
  description = "allows http access from LoadBalancer"
  vpc_id      = aws_vpc.task17-skryvoruchko-vpc.id
  tags = {
    Name = "task17-skryvoruchko-http-inbound-asg"
  }
}


resource "aws_security_group_rule" "allow_ingress_port_80" {

  description = "allows http access from safe IP-range to a LoadBalancer"

  type      = "ingress"
  from_port = 80
  to_port   = 80
  protocol  = "tcp"

  security_group_id        = aws_security_group.http-inbound-asg.id
  source_security_group_id = aws_security_group.task17-skryvoruchko-lb_security_group.id
}

resource "aws_security_group_rule" "allow_egress_all" {

  description = "allows egress to all"

  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.http-inbound-asg.id
  #source_security_group_id = aws_security_group.task17-skryvoruchko-lb_security_group.id
}

#NETWORKING
#VPC
resource "aws_vpc" "task17-skryvoruchko-vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"
  tags = {
    Name = "task17-skryvoruchko-vpc"
  }
}

resource "aws_internet_gateway" "task17-skryvoruchko-igw" {
  vpc_id = aws_vpc.task17-skryvoruchko-vpc.id
}

#SUBNETS
resource "aws_subnet" "task17-skryvoruchko-public-1" {
  vpc_id            = aws_vpc.task17-skryvoruchko-vpc.id
  cidr_block        = "10.0.0.0/24"
  availability_zone = "eu-central-1a"
  tags = {
    Name = "task17-skryvoruchko-public-1"
  }
}

resource "aws_subnet" "task17-skryvoruchko-public-2" {
  vpc_id            = aws_vpc.task17-skryvoruchko-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-central-1b"
  tags = {
    Name = "task17-skryvoruchko-public-2"
  }
}

resource "aws_subnet" "task17-skryvoruchko-private-1" {
  vpc_id            = aws_vpc.task17-skryvoruchko-vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-central-1a"
  tags = {
    Name = "task17-skryvoruchko-private-1"
  }
}

resource "aws_subnet" "task17-skryvoruchko-private-2" {
  vpc_id            = aws_vpc.task17-skryvoruchko-vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "eu-central-1b"
  tags = {
    Name = "task17-skryvoruchko-private-2"
  }
}


#ROUTETABLES
#PUBLIC RT
resource "aws_route_table" "task17-skryvoruchko-public-rt" {
  vpc_id = aws_vpc.task17-skryvoruchko-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.task17-skryvoruchko-igw.id
  }

  tags = {
    Name = "Serhii-Kryvoruchko-01-subnet-public"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.task17-skryvoruchko-public-1.id
  route_table_id = aws_route_table.task17-skryvoruchko-public-rt.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.task17-skryvoruchko-public-2.id
  route_table_id = aws_route_table.task17-skryvoruchko-public-rt.id
}


#Private RT
resource "aws_route_table" "task17-skryvoruchko-private-rt" {
  vpc_id = aws_vpc.task17-skryvoruchko-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.task17-skryvoruchko-nat.id
  }

  tags = {
    Name = "Serhii-Kryvoruchko-02-subnet-private"
  }
}

resource "aws_route_table_association" "private-a" {
  subnet_id      = aws_subnet.task17-skryvoruchko-private-1.id
  route_table_id = aws_route_table.task17-skryvoruchko-private-rt.id
}

resource "aws_route_table_association" "private-b" {
  subnet_id      = aws_subnet.task17-skryvoruchko-private-2.id
  route_table_id = aws_route_table.task17-skryvoruchko-private-rt.id
}



#NAT
resource "aws_nat_gateway" "task17-skryvoruchko-nat" {
  connectivity_type = "public"
  subnet_id         = aws_subnet.task17-skryvoruchko-public-1.id

  tags = {
    Name = "task17-skryvoruchko-nat"
  }
  # To ensure proper ordering, it is recommended to add an explicit dependency on the Internet Gateway for the VPC.
  depends_on    = [aws_internet_gateway.task17-skryvoruchko-igw]
  allocation_id = aws_eip.task17-skryvoruchko-nat-eip.id
}
#ASSIGN ELASTIC IP TO NAT
resource "aws_eip" "task17-skryvoruchko-nat-eip" {
  vpc = true
}
