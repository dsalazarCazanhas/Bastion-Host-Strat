# Bastion Host

A hardened SSH jump server on AWS that gives authorized operators secure access to a private server without exposing it to the internet. Fully automated with Terraform (infrastructure) and Ansible (configuration).

## Architecture

```
                   ┌──────────────────────────────────────────────┐
                   │              AWS VPC (10.0.0.0/16)           │
                   │                                              │
 [Operator]        │  Public Subnet          Private Subnet       │
 local SSH keys    │  10.0.1.0/24            10.0.2.0/24          │
       │           │  ┌──────────────┐       ┌────────────────┐  │
       │  SSH :22  │  │ Bastion Host │──:22──│ Private Server │  │
       └──────────────▶ Elastic IP   │       │ No public IP   │  │
       (ProxyJump) │  │ sg: your IP  │       │ sg: bastion SG │  │
                   │  └──────────────┘       └────────────────┘  │
                   │          │ Internet Gateway                  │
                   └──────────────────────────────────────────────┘
```

Both private keys stay on the operator's machine. `ProxyJump` routes through the bastion without forwarding the SSH agent.

See [docs/architecture.md](docs/architecture.md) for full design decisions.

---

## Stack

| Layer | Tool |
|---|---|
| Cloud | AWS (us-east-2) |
| Infrastructure | Terraform >= 1.6, AWS provider ~> 6.0 |
| OS | Ubuntu 24.04 LTS (Noble) — Canonical AMI |
| Configuration | Ansible |
| SSH hardening | Custom `sshd_config` (CIS-aligned) |
| Brute-force protection | fail2ban (systemd journal backend) |
| MFA | libpam-google-authenticator (TOTP) |

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.6
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) >= 2.14
- AWS CLI configured (`aws configure`) with permissions to create VPC, EC2, and Security Group resources
- Two Ed25519 SSH key pairs (see step 1 below)

---

## Deployment

### 1. Generate SSH key pairs

```bash
ssh-keygen -t ed25519 -f ~/.ssh/bastion_key -C "bastion"
ssh-keygen -t ed25519 -f ~/.ssh/private_server_key -C "private-server"
chmod 600 ~/.ssh/bastion_key ~/.ssh/private_server_key
```

### 2. Find your public IP

```bash
curl -s https://checkip.amazonaws.com
```

### 3. Configure Terraform variables

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — fill in allowed_cidr, bastion_public_key, private_server_public_key
```

### 4. Deploy infrastructure

```bash
terraform init
terraform plan
terraform apply
```

### 5. Configure your SSH client

```bash
# Print the ready-to-paste SSH config block
terraform output ssh_config_snippet
```

Paste the output into `~/.ssh/config`. Full guide: [docs/ssh-client-config.md](docs/ssh-client-config.md).

### 6. Run Ansible

```bash
cd ../ansible/
cp inventory/hosts.ini.example inventory/hosts.ini
# Edit hosts.ini — fill in BASTION_EIP and PRIVATE_IP from: terraform output
# Also edit inventory/group_vars/private.yml — replace BASTION_EIP with the real bastion IP
ansible-playbook playbooks/site.yml
```

### 7. Enroll TOTP (MFA on bastion)

```bash
ssh bastion
google-authenticator --time-based --disallow-reuse --force --rate-limit=3 --rate-time=30 --window-size=3
```

Scan the QR code with any TOTP app (Google Authenticator, Authy, etc.).

Once enrolled, enforce MFA for all users:

```bash
# Set mfa_nullok: false in ansible/playbooks/roles/mfa/defaults/main.yml
ansible-playbook playbooks/bastion.yml
```

---

## Connecting

```bash
# Bastion host directly
ssh bastion

# Private server via ProxyJump (single command from local machine)
ssh private-server
```

---

## Repository structure

```
├── terraform/
│   ├── main.tf                    # Provider + Ubuntu AMI data source
│   ├── variables.tf               # Input variables (with validation)
│   ├── vpc.tf                     # VPC, subnets, IGW, route tables
│   ├── security_groups.tf         # SG bastion + SG private
│   ├── instances.tf               # EC2 instances, EIP, key pairs
│   ├── outputs.tf                 # IPs + ssh_config_snippet
│   └── terraform.tfvars.example   # Template — copy to terraform.tfvars
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/
│   │   ├── hosts.ini.example              # Template — copy to hosts.ini
│   │   └── group_vars/
│   │       └── private.yml                # ProxyCommand for private server (edit BASTION_EIP)
│   └── playbooks/
│       ├── site.yml               # Entry point: bastion → private
│       ├── bastion.yml
│       ├── private.yml
│       └── roles/
│           ├── ssh-hardening/     # Hardened sshd_config (both hosts)
│           ├── fail2ban/          # Brute-force protection (bastion only)
│           └── mfa/               # TOTP via PAM (bastion only)
└── docs/
    ├── architecture.md            # Network diagram + design decisions
    └── ssh-client-config.md       # Step-by-step SSH + MFA guide
```

---

## Security notes

- `terraform.tfvars` and `inventory/hosts.ini` are git-ignored — they contain real IPs and public key material.
- Private keys never leave the operator's machine and are never committed.
- `allowed_cidr` must be a `/32` — the Terraform variable has a validation rule that rejects `/0`.
- If your IP changes, update `allowed_cidr` in `terraform.tfvars` and run `terraform apply` to refresh the Security Group rule.

---

## Teardown

```bash
cd terraform/
terraform destroy
```

This removes all AWS resources created by this project. The Elastic IP is released and billing stops.

---

> A journey to grow up from [Roadmap.sh](https://roadmap.sh/projects/bastion-host)
