# ──────────────────────────────────────────
# Availability Zone — picks the first available AZ in the region
# Avoids hardcoding "us-east-2a", works with any region
# ──────────────────────────────────────────
data "aws_availability_zones" "available" {
  state = "available"
}

# ──────────────────────────────────────────
# VPC
# ──────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# ──────────────────────────────────────────
# Subnets
# ──────────────────────────────────────────

# Public subnet — Bastion Host lives here (has a route to the IGW)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false # Bastion uses an explicit Elastic IP, not auto-assign

  tags = {
    Name = "${var.project_name}-subnet-public"
  }
}

# Private subnet — Private Server lives here (no route to the IGW)
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-subnet-private"
  }
}

# ──────────────────────────────────────────
# Internet Gateway — entry/exit point between the VPC and the internet
# Only the public subnet will have a route to it
# ──────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ──────────────────────────────────────────
# Route Tables
# ──────────────────────────────────────────

# Public route table: all non-local traffic exits through the IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-rt-public"
  }
}

# Associate the public subnet with the public route table
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Private route table: local VPC traffic only
# No 0.0.0.0/0 route — the private server cannot reach the internet
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-rt-private"
  }
}

# Associate the private subnet with the private route table
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
