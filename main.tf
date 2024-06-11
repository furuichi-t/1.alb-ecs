resource "aws_vpc" "ecs-vpc" {  
  cidr_block = "10.0.0.0/16"
}


resource "aws_subnet" "ecs_subnet1" { 
  vpc_id            = aws_vpc.ecs-vpc.id
  cidr_block        = "10.0.2.0/24" 
  availability_zone = "ap-northeast-1a"
  map_public_ip_on_launch = false 
}

resource "aws_subnet" "ecs_subnet2" { 
  vpc_id            = aws_vpc.ecs-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-northeast-1c"
  map_public_ip_on_launch = false
}

resource "aws_internet_gateway" "ecs-igw" { 
  vpc_id = aws_vpc.ecs-vpc.id 
}

resource "aws_route_table" "rtb-public" { 
  vpc_id = aws_vpc.ecs-vpc.id 
}

resource "aws_route" "route" { 
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.ecs-igw.id
  route_table_id = aws_route_table.rtb-public.id
}

resource "aws_route_table_association" "rtba" { 
  route_table_id = aws_route_table.rtb-public.id 
  subnet_id = aws_subnet.ecs_subnet1.id
}

resource "aws_route_table_association" "rtba2" { 
  route_table_id = aws_route_table.rtb-public.id
  subnet_id = aws_subnet.ecs_subnet2.id
}

resource "aws_security_group" "alb-sg" { 
  name   = "ecs-alb-sg"
  vpc_id = aws_vpc.ecs-vpc.id

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
}

resource "aws_security_group" "ecs-sg-service" { 
  name   = "ecs-sg"
  vpc_id = aws_vpc.ecs-vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.ecs-sg.id]
  }
   
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_ecs_cluster" "ecs-cluster" { 
  name = "ecs-cluster"
}

resource "aws_ecs_task_definition" "ecs-task" {
  family                   = "ecs-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn 

  container_definitions = jsonencode([ 
    {
      "name"      : "furuichitest", 
      "image"     : "httpd:2.4", 
      "portMappings" : [
        {
          "containerPort" : 80, 
          "hostPort" : 80
        }
      ],
      "memory" : 256
      "cpu" : 256
    }
  ])
} 

resource "aws_iam_role" "ecs_task_execution_role" { 
  name = "iam-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com"},
        Action = "sts:AssumeRole"
      }
    ]
  })
  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
}

resource "aws_lb" "ecs-alb" { 
  name               = "ecs-alb"
  internal           = false 
  load_balancer_type = "application" 
  security_groups    = [aws_security_group.alb-sg.id] 
  subnets            = [aws_subnet.ecs_subnet1.id, aws_subnet.ecs_subnet2.id] 

  enable_deletion_protection = false 
}

resource "aws_lb_target_group" "ecs-tg" { 
  name     = "ecs-tg"
  port     = 80 
  protocol = "HTTP" 
  vpc_id   = aws_vpc.ecs-vpc.id 
  target_type = "ip" 
}

resource "aws_lb_listener" "ecs-alb-listener" { 
  load_balancer_arn = aws_lb.ecs-alb.arn        
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward" 
    target_group_arn = aws_lb_target_group.ecs-tg.arn
  }
}


resource "aws_ecs_service" "ecs-service" {
  name            = "ecsservice"
  cluster         = aws_ecs_cluster.ecs-cluster.id
  task_definition = aws_ecs_task_definition.ecs-task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.ecs_subnet1.id, aws_subnet.ecs_subnet2.id]
    security_groups  = [aws_security_group.ecs-sg-service.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs-tg.arn
    container_name   = "ecs-container"
    container_port   = 80
  }
    lifecycle {
    ignore_changes = [
      task_definition,
      desired_count,
    ]
  }
}


