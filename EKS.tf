module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.15.1"

  name                   = var.cluster_name        
  kubernetes_version     = var.cluster_version      
  # name               = "k8s_aws_eks_cluster"
  # kubernetes_version = "1.33"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Endpoint access
  endpoint_public_access  = true
  endpoint_private_access = true
  
  # Giới hạn public endpoint chỉ từ IP của bạn (tăng bảo mật, khuyến nghị cho dev)
  # endpoint_public_access_cidrs = ["0.0.0.0/0"]  # Uncomment nếu muốn giới hạn CIDR public (default là full open)

  # Attach SG bổ sung cho control plane (thay vì cluster_security_group_id)
  additional_security_group_ids = [aws_security_group.eks_control_plane.id]

  # Managed Node Groups
  eks_managed_node_groups = {
    default = {
      min_size     = 1
      max_size     = 3
      desired_size = var.desired_node_count

      instance_types = [var.node_instance_type]
      capacity_type  = "ON_DEMAND"
      
      # Attach SG cho worker nodes
      additional_security_group_ids = [aws_security_group.eks_nodes.id]  # SG cho worker nodes

      # IAM policy bổ sung cho nodes (SSM để debug/compliance)
      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }

      update_config = {
        max_unavailable_percentage = 33
      }
    }
  }

  # Enable IRSA
  enable_irsa = true

  # Cho phép creator (bạn) có admin quyền (khuyến nghị cho dev)
  enable_cluster_creator_admin_permissions = true

  # Tags
  tags = {
    Environment = "dev"
    Name        = var.cluster_name
  }
}