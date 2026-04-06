# ──────────────────────────────────────────
# Key Pairs — public keys uploaded to AWS
# Private keys never leave the operator's machine
# ──────────────────────────────────────────

resource "aws_key_pair" "bastion" {
  key_name   = "${var.project_name}-bastion-key"
  public_key = var.bastion_public_key
}

resource "aws_key_pair" "private" {
  key_name   = "${var.project_name}-private-server-key"
  public_key = var.private_server_public_key
}

# ──────────────────────────────────────────
# Bastion Host
# ──────────────────────────────────────────

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  key_name                    = aws_key_pair.bastion.key_name
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = false # EIP is assigned explicitly below

  # IMDSv2 only — prevents SSRF attacks from stealing instance credentials
  # via the metadata endpoint (169.254.169.254)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-bastion"
    Role = "bastion"
  }
}

# Elastic IP — static public address for the bastion host
# Decoupled from the instance so it survives stop/start cycles
resource "aws_eip" "bastion" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-eip-bastion"
  }
}

resource "aws_eip_association" "bastion" {
  instance_id   = aws_instance.bastion.id
  allocation_id = aws_eip.bastion.id
}

# ──────────────────────────────────────────
# Private Server
# ──────────────────────────────────────────

resource "aws_instance" "private" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.private.id
  key_name                    = aws_key_pair.private.key_name
  vpc_security_group_ids      = [aws_security_group.private.id]
  associate_public_ip_address = false # Private server must not have a public IP

  # IMDSv2 only
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-private"
    Role = "private"
  }
}
