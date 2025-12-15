terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# -----------------------------
# Networking (Terraform-managed)
# -----------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "${var.project}-igw" }
}

# Public subnets (for Bastion + NAT)
resource "aws_subnet" "public" {
  for_each                = toset(var.azs)
  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.value
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, index(var.azs, each.value))
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project}-public-${each.value}"
    Tier = "public"
  }
}

# Private subnets (for workload nodes)
resource "aws_subnet" "private" {
  for_each                = toset(var.azs)
  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.value
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, 8 + index(var.azs, each.value))
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project}-private-${each.value}"
    Tier = "private"
  }
}

# Route tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "${var.project}-rt-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway (single NAT for simplicity/cost; can be per-AZ for HA)
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.project}-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = values(aws_subnet.public)[0].id
  tags          = { Name = "${var.project}-nat" }
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "${var.project}-rt-private" }
}

resource "aws_route" "private_to_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "private_assoc" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# -----------------------------
# Security (Terraform-managed)
# -----------------------------
resource "aws_security_group" "bastion_sg" {
  name        = "${var.project}-bastion-sg"
  description = "SSH access to bastion"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from admin CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-bastion-sg" }
}

resource "aws_security_group" "private_sg" {
  name        = "${var.project}-private-sg"
  description = "Private workload SG"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  # Example: allow internal service-to-service traffic
  ingress {
    description = "Internal TCP"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound (via NAT)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-private-sg" }
}

# -----------------------------
# Compute (Terraform-managed)
# -----------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.bastion_instance_type
  subnet_id                   = values(aws_subnet.public)[0].id
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  key_name                    = var.ssh_key_name
  associate_public_ip_address = true

  tags = {
    Name = "${var.project}-bastion"
    Role = "bastion"
  }
}

# Private nodes that represent the data platform components (example)
resource "aws_instance" "data_nodes" {
  count                  = var.data_node_count
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.data_node_instance_type
  subnet_id              = element(values(aws_subnet.private)[*].id, count.index % length(var.azs))
  vpc_security_group_ids = [aws_security_group.private_sg.id]
  key_name               = var.ssh_key_name

  tags = {
    Name = "${var.project}-data-node-${count.index + 1}"
    Role = "data-platform"
  }
}

# Attached EBS volumes for data nodes (separate data disks)
resource "aws_ebs_volume" "data_disks" {
  count             = var.data_node_count
  availability_zone = aws_instance.data_nodes[count.index].availability_zone
  size              = var.data_disk_gb
  type              = "gp3"

  tags = {
    Name = "${var.project}-data-disk-${count.index + 1}"
  }
}

resource "aws_volume_attachment" "data_disks_attach" {
  count       = var.data_node_count
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data_disks[count.index].id
  instance_id = aws_instance.data_nodes[count.index].id
}
