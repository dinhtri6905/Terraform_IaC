# Xóa folder .terraform (recursive, force, không hỏi xác nhận)
Remove-Item -Path .terraform -Recurse -Force

# Xóa file lock nếu tồn tại (để Terraform init lại từ đầu)
Remove-Item -Path .terraform.lock.hcl -Force -ErrorAction SilentlyContinue


# Xây dựng hạ tầng AWS EKS với Terraform (Compliance as Code - Phần Infrastructure)

## Mô tả dự án
Dự án này sử dụng **Terraform** để tự động hóa việc triển khai hạ tầng cloud trên AWS cho ứng dụng microservices (hệ thống thương mại điện tử với các service: User, Product, Order, Notification).

Hạ tầng chính bao gồm:
- VPC với public/private subnets, NAT Gateway
- Security Groups (SG) cho EKS control plane và worker nodes
- Amazon EKS Cluster (Kubernetes managed) với managed node groups

Mục tiêu:
- Đảm bảo bảo mật theo các chuẩn CIS Benchmarks và PCI-DSS (private subnets, least-privilege SG, IRSA)
- Dễ dàng tích hợp vào pipeline CI/CD (GitHub Actions) và Compliance as Code (Checkov, OPA/Conftest)
- Hỗ trợ triển khai ứng dụng containerized trên EKS

## Cấu trúc thư mục dự án
.
├── .terraform/                  # Thư mục tự động sinh bởi Terraform (không commit lên Git)
│   ├── modules/                 # Các module tải về từ registry (vpc, eks, eks.kms, ...)
│   └── providers/               # Binary provider plugins (aws, null, time, tls, ...)
├── .terraform.lock.hcl          # Lock file phiên bản provider/module (NÊN COMMIT)
├── eks.tf                       # Định nghĩa EKS cluster và node groups
├── outputs.tf                   # Các giá trị output (endpoint, kubeconfig command, vpc_id, ...)
├── provider.tf                  # Khai báo AWS provider version 6.34.0
├── variables.tf                 # Các biến cấu hình (region, cluster_name, your_ip, ...)
├── vpc.tf                       # Định nghĩa VPC, subnets, NAT Gateway, Security Groups
└── README.md                    # Tài liệu này


### Giải thích các file chính và mục đích

- **provider.tf**  
  Khai báo provider AWS với version cố định **6.34.0** (để đảm bảo tính tương thích và tránh breaking changes).

- **variables.tf**  
  Định nghĩa các biến có thể tùy chỉnh (region, CIDR VPC, tên cluster, IP của bạn để giới hạn SSH/HTTPS, loại instance node, ...).  
  → Giúp dễ dàng thay đổi môi trường (dev/staging/prod) mà không sửa code.

- **vpc.tf**  
  Tạo VPC hoàn chỉnh với:
  - Public subnets (cho Load Balancer)
  - Private subnets (cho EKS worker nodes – bảo mật cao)
  - NAT Gateway (cho phép nodes private ra internet)
  - Security Groups:
    - `eks-control-plane-sg`: Chỉ cho phép HTTPS (443) từ IP của bạn → bảo vệ API server EKS
    - `eks-nodes-sg`: Cho phép SSH debug từ IP bạn, và giao tiếp nội bộ với control plane

- **eks.tf**  
  Tạo EKS cluster với:
  - Control plane ở private subnets
  - Endpoint public + private (có thể giới hạn public CIDR)
  - Managed node groups (EC2-based, autoscaling)
  - IRSA (IAM Roles for Service Accounts) – cần cho addons như ALB Controller
  - Attach SG bổ sung cho control plane và nodes
  - Cho phép user IAM tạo cluster có quyền admin (dễ quản lý kubectl)

- **outputs.tf**  
  Xuất ra các giá trị quan trọng sau khi apply:
  - Cluster endpoint
  - Security group ID
  - Lệnh cập nhật kubeconfig (`aws eks update-kubeconfig ...`)
  - VPC ID

- **.terraform.lock.hcl**  
  Lock file ghi lại chính xác version của provider và module đã tải.  
  → Đảm bảo mọi người (hoặc CI/CD) chạy cùng version, tránh lỗi "works on my machine".

## Cách sử dụng
### Các lệnh cơ bản

1. Khởi tạo dự án (tải module & provider)
```powershell
terraform init 
```

2. Kiểm tra syntax
```powershell
terraform validate
```

3. Xem kế hoạch triển khai
```powershell
terraform plan
```

4. Triển khai hạ tầng
```powershell
terraform apply → Nhập yes để xác nhận 
```

4. Kết nối đến cluster
```bash
aws eks update-kubeconfig --region ap-southeast-1 --name ecommerce-eks-cluster
kubectl get nodes
```

5. Xóa hạ tầng 
```powershell
terraform destroy
```

### Tích hợp Compliance as Code

Scan IaC bằng Checkov:
```powershell
checkov -d .
```
Tích hợp vào GitHub Actions: Thêm step Checkov trước terraform apply để chặn deploy nếu vi phạm CIS/PCI. 

## Vai trò cụ thể từng thành phần

### VPC (Virtual Private Cloud)
- Đây là "mạng riêng ảo" của bạn trên AWS, giống như một mạng LAN riêng trong data center.
- CIDR: 10.0.0.0/16 → đủ lớn để mở rộng sau này.
- Mục đích: Tất cả tài nguyên (EKS nodes, load balancer, RDS nếu có) nằm trong VPC này → bảo mật cao, dễ kiểm soát traffic.

### Public Subnets (ví dụ: 10.0.101.0/24, 10.0.102.0/24, ...)
- Có route đến Internet Gateway (IGW) → có thể nhận traffic từ internet.
- Dùng để đặt: NAT Gateway, Load Balancer (ALB/NLB) cho ứng dụng microservices (User API, Product API cần expose public).
- Tags kubernetes.io/role/elb = 1 → Kubernetes biết đặt Load Balancer vào đây.

### Private Subnets (ví dụ: 10.0.1.0/24, 10.0.2.0/24, ...)
- Không có route trực tiếp ra internet (không public IP).
- EKS worker nodes (EC2 instances chạy pods) được đặt ở đây → bảo mật cao nhất (theo CIS Benchmarks: nodes không expose public).
- Tags kubernetes.io/role/internal-elb = 1 → cho internal load balancer nếu cần.
- Lý do quan trọng: Nếu nodes ở public, dễ bị tấn công trực tiếp từ internet → vi phạm PCI-DSS và CIS.

### NAT Gateway (single NAT để tiết kiệm chi phí)
- Đặt ở public subnet.
- Cho phép nodes ở private subnet ra internet (pull Docker image từ ECR, gọi AWS services như S3, Secrets Manager, hoặc update packages).
- Nhưng không cho phép inbound từ internet vào nodes → bảo vệ pods/microservices.
- Đây là lý do private nodes vẫn hoạt động bình thường (egress only).

### Security Groups (SG)
- eks-control-plane-sg: Chỉ cho phép HTTPS (port 443) từ IP của bạn (var.your_ip) → bảo vệ API server EKS (kubectl access). Không cho ai khác vào.
- eks-nodes-sg:
  + Cho phép SSH (port 22) từ IP bạn → debug khi cần.
  + Cho phép traffic nội bộ từ control plane SG → EKS control plane giao tiếp với nodes.
  + Egress full → nodes ra ngoài được.
→ Áp dụng nguyên tắc least privilege (chỉ mở những port cần thiết) → tuân thủ PCI-DSS và CIS.

### EKS Cluster
- Control plane: AWS quản lý (bạn không thấy instance).
- Worker nodes: Managed node groups (EC2 t3.medium, autoscaling 1-3 nodes) đặt ở private subnets.
- Endpoint: Public + Private → bạn có thể kubectl từ máy local (public), nhưng cluster vẫn an toàn.
- IRSA (enable_irsa = true): Cho phép pods dùng IAM roles → an toàn hơn secrets hardcode (tuân thủ CIS).