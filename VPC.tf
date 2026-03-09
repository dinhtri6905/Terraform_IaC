module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.0"

  name = "my-vpc"
  cidr = var.vpc_cidr
  # cidr = "10.0.0.0/16"

  azs             = var.availability_zones
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets
  # azs             = ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]
  # private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  # public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway     = true  // Cho private subnets ra internet (ví dụ: pull images)
  single_nat_gateway     = true  // Tiết kiệm chi phí, dùng 1 NAT cho tất cả AZ
  enable_vpn_gateway     = false
  one_nat_gateway_per_az = false

  // Tags cho compliance (dễ audit CIS/PCI-DSS)
  tags = {
    Name        = "my-vpc"
    Environment = "dev"
  }

  // Tags cho Kubernetes (EKS load balancers)
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}


// SG cho EKS Control Plane
resource "aws_security_group" "eks_control_plane" {
  name        = "eks-control-plane-sg"
  description = "Security group for EKS control plane"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443  // HTTPS cho kubectl access
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]  // Chỉ cho phép IP của bạn
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]  // Cho phép outbound
  }

  tags = {
    Name = "eks-control-plane-sg"
  }
}

// SG cho EKS Worker Nodes
resource "aws_security_group" "eks_nodes" {
  name        = "eks-nodes-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22  // SSH cho debug (giới hạn IP)
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
  }

  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_control_plane.id]  // Cho control plane giao tiếp với nodes
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-nodes-sg"
  }
}