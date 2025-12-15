# --- Required ---
admin_cidr   = "203.0.113.10/32"     # <-- replace with your public IP/CIDR
ssh_key_name = "future20-keypair"    # <-- replace with your existing EC2 key pair name

# --- Optional overrides ---
project                 = "future20"
aws_region              = "eu-central-1"
azs                     = ["eu-central-1a", "eu-central-1b"]
vpc_cidr                = "10.20.0.0/16"
bastion_instance_type   = "t3.micro"
data_node_count         = 2
data_node_instance_type = "t3.large"
data_disk_gb            = 200
