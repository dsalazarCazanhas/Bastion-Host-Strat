# ──────────────────────────────────────────
# Security Group — Bastion Host
# ──────────────────────────────────────────

resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-sg-bastion"
  description = "Controls traffic to and from the bastion host"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-sg-bastion"
  }
}

# Inbound: SSH only from the operator's known IP — never 0.0.0.0/0
resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  security_group_id = aws_security_group.bastion.id
  description       = "SSH access from the operator IP only"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = var.allowed_cidr
}

# Outbound: SSH to the private subnet — bastion can only initiate SSH to private server
resource "aws_vpc_security_group_egress_rule" "bastion_to_private_ssh" {
  security_group_id = aws_security_group.bastion.id
  description       = "SSH to the private subnet"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = aws_subnet.private.cidr_block
}

# Outbound: HTTPS to the internet — required for apt package installation (fail2ban, google-authenticator)
resource "aws_vpc_security_group_egress_rule" "bastion_https" {
  security_group_id = aws_security_group.bastion.id
  description       = "HTTPS outbound for package manager (apt)"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# Outbound: HTTP to the internet — required for apt repository metadata (some mirrors use HTTP)
resource "aws_vpc_security_group_egress_rule" "bastion_http" {
  security_group_id = aws_security_group.bastion.id
  description       = "HTTP outbound for package manager (apt mirrors)"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# ──────────────────────────────────────────
# Security Group — Private Server
# ──────────────────────────────────────────

resource "aws_security_group" "private" {
  name        = "${var.project_name}-sg-private"
  description = "Allows SSH only from the bastion host security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-sg-private"
  }
}

# Inbound: SSH only from the bastion security group
# Referencing the SG (not the IP) is more robust — survives EIP reassociation
resource "aws_vpc_security_group_ingress_rule" "private_ssh_from_bastion" {
  security_group_id            = aws_security_group.private.id
  description                  = "SSH from bastion host security group only"
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.bastion.id
}

# No outbound rules — the private server has no route to the internet (no IGW, no NAT)
# AWS Security Groups are stateful: return traffic for established connections
# is automatically allowed without explicit egress rules
