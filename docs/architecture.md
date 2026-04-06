# Architecture

## Network diagram

```
                        ┌─────────────────────────────────────────────────────┐
                        │                  AWS VPC (10.0.0.0/16)              │
                        │                                                     │
                        │  ┌──────────────────────┐   ┌───────────────────┐  │
 [Operator]             │  │   Public Subnet       │   │  Private Subnet   │  │
 ~/.ssh/bastion_key     │  │   10.0.1.0/24         │   │  10.0.2.0/24      │  │
 ~/.ssh/private_key     │  │                       │   │                   │  │
       │                │  │  ┌─────────────────┐  │   │  ┌─────────────┐ │  │
       │   SSH :22      │  │  │  Bastion Host   │  │   │  │Private Svr  │ │  │
       └───────────────────▶│  Ubuntu 24.04    │──────▶│ Ubuntu 24.04│ │  │
       (ProxyJump)      │  │  │  Elastic IP     │  │   │  10.0.2.x   │ │  │
                        │  │  │  sg: :22 from   │  │   │  sg: :22    │ │  │
                        │  │  │  allowed_cidr   │  │   │  from bastion│ │  │
                        │  │  └─────────────────┘  │   │  SG only    │ │  │
                        │  │          ▲             │   └─────────────┘ │  │
                        │  └──────────┼─────────────┘   └───────────────┘  │
                        │             │                                     │
                        │     Internet Gateway                              │
                        └─────────────────────────────────────────────────────┘
                                      │
                                  Internet
```

The operator's machine holds both private keys locally. `ProxyJump` routes the
connection through the bastion without forwarding the SSH agent — the private
server key is used directly from the client via the encrypted tunnel.

---

## Design decisions

### Single public entry point
Only the bastion host has a public IP (Elastic IP). The private server has no
public IP and its Security Group accepts port 22 exclusively from the bastion's
Security Group — not from a CIDR range, so the rule survives EIP reassociation.

### ProxyJump over Agent Forwarding
`ProxyJump` (SSH 7.3+) opens a `direct-tcpip` channel through the bastion.
The client's SSH agent is never forwarded. If the bastion is compromised, the
attacker cannot use the operator's keys for lateral movement.

`AgentForwarding` is explicitly disabled in `sshd_config` on both hosts.

### Separate Ed25519 keys per server
Each host has its own key pair. Compromise of one key does not grant access to
the other host. Ed25519 is preferred over RSA: smaller keys, faster
verification, not vulnerable to the same timing attacks as RSA.

### IMDSv2 enforced
Both instances require `http_tokens = "required"` (IMDSv2). This blocks SSRF
attacks that attempt to steal IAM credentials via the metadata endpoint
`169.254.169.254`.

### Encrypted EBS volumes
Root volumes use `gp3` + `encrypted = true`. If a snapshot is taken or the
volume is reattached to another instance, data remains unreadable without the
AWS KMS key.

### fail2ban on bastion only
The private server is not reachable from the internet. Installing fail2ban
there would add no security value. It is applied exclusively to the bastion,
which is the only host exposed to internet-sourced SSH attempts.

### MFA on bastion only
The private server is only reachable from within the VPC. MFA is applied on
the bastion where external authentication happens. The authentication chain is:

```
[1] SSH public key   — verified by sshd (Ed25519)
[2] TOTP code        — verified by PAM (pam_google_authenticator)
```

### mfa_nullok during initial setup
The `mfa` role deploys with `mfa_nullok: true` so users who have not yet
enrolled their TOTP secret can still log in during the setup window. Once all
operators have enrolled, set `mfa_nullok: false` and re-run the playbook.

### Private route table (explicit)
The private subnet has an explicit route table with no `0.0.0.0/0` route. This
prevents the private server from reaching the internet even if someone adds a
NAT Gateway to the VPC later — it would need an explicit route table update.

---

## Resource inventory

| Resource | Name | Purpose |
|---|---|---|
| `aws_vpc` | `bastion-host-vpc` | Isolated network boundary |
| `aws_subnet` (public) | `bastion-host-subnet-public` | Bastion host placement |
| `aws_subnet` (private) | `bastion-host-subnet-private` | Private server placement |
| `aws_internet_gateway` | `bastion-host-igw` | Internet access for public subnet |
| `aws_route_table` (public) | `bastion-host-rt-public` | Routes `0.0.0.0/0` to IGW |
| `aws_route_table` (private) | `bastion-host-rt-private` | Local VPC traffic only |
| `aws_security_group` (bastion) | `bastion-host-sg-bastion` | Port 22 from `allowed_cidr` only |
| `aws_security_group` (private) | `bastion-host-sg-private` | Port 22 from bastion SG only |
| `aws_instance` (bastion) | `bastion-host-bastion` | Jump server, IMDSv2, gp3 encrypted |
| `aws_instance` (private) | `bastion-host-private` | Internal server, no public IP |
| `aws_eip` | `bastion-host-eip-bastion` | Static public IP for bastion |
| `aws_key_pair` (bastion) | `bastion-host-bastion-key` | Ed25519 public key upload |
| `aws_key_pair` (private) | `bastion-host-private-server-key` | Ed25519 public key upload |

---

## Ansible role dependency map

```
bastion host
├── ssh-hardening   (AllowTcpForwarding yes, base sshd_config)
├── fail2ban        (monitors sshd via systemd journal)
└── mfa             (PAM TOTP + sshd drop-in 99-mfa.conf)

private server
└── ssh-hardening   (AllowTcpForwarding no, base sshd_config)
```
