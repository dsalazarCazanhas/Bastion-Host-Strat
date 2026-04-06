# SSH Client Configuration

## 1. Generate keys (run once, on your local machine)

```bash
# Key for the bastion host
ssh-keygen -t ed25519 -f ~/.ssh/bastion_key -C "bastion"

# Key for the private server
ssh-keygen -t ed25519 -f ~/.ssh/private_server_key -C "private-server"
```

Set restrictive permissions (required by SSH):

```bash
chmod 600 ~/.ssh/bastion_key ~/.ssh/private_server_key
chmod 644 ~/.ssh/bastion_key.pub ~/.ssh/private_server_key.pub
```

---

## 2. Get the IPs from Terraform after `terraform apply`

```bash
cd terraform/
terraform output bastion_public_ip
terraform output private_server_ip
# Or print the ready-to-paste SSH config block:
terraform output ssh_config_snippet
```

---

## 3. Add to `~/.ssh/config`

```
Host bastion
    HostName <bastion_public_ip>
    User ubuntu
    IdentityFile ~/.ssh/bastion_key
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 3

Host private-server
    HostName <private_server_ip>
    User ubuntu
    IdentityFile ~/.ssh/private_server_key
    IdentitiesOnly yes
    ProxyJump bastion
```

> `IdentitiesOnly yes` prevents the SSH agent from offering other loaded keys
> before the specified one — avoids spurious `MaxAuthTries` exhaustion.

---

## 4. Connect

```bash
# Connect to the bastion directly
ssh bastion

# Connect to the private server via ProxyJump (transparent, one command)
ssh private-server

# First connection will prompt to accept the host fingerprint.
# Verify it matches the fingerprint shown in the AWS Console (EC2 → Instance → Connect).
```

---

## 5. TOTP enrollment on the bastion (MFA setup, run once)

After Ansible has configured MFA, SSH into the bastion and enroll:

```bash
ssh bastion

# Once logged in, run as the ubuntu user:
google-authenticator \
  --time-based \
  --disallow-reuse \
  --force \
  --rate-limit=3 \
  --rate-time=30 \
  --window-size=3
```

Scan the QR code with Google Authenticator, Authy, or any TOTP-compatible app.

Save the emergency scratch codes in a secure location (password manager).

After all operators have enrolled, enforce MFA for everyone:

```bash
# In ansible/playbooks/roles/mfa/defaults/main.yml
mfa_nullok: false

# Re-run the bastion playbook
ansible-playbook playbooks/bastion.yml
```

---

## 6. Verify fail2ban is active (on the bastion)

```bash
ssh bastion
sudo fail2ban-client status sshd
```

Expected output shows active jail, currently banned IPs, and total failed attempts.

To manually unban an IP:

```bash
sudo fail2ban-client set sshd unbanip <IP>
```

---

## Security reminders

- **Never copy private keys to any server.** `ProxyJump` uses them locally.
- **Never commit `terraform.tfvars` or `hosts.ini`** — both are git-ignored.
- **Rotate keys** if you suspect compromise: generate new pair, update `terraform.tfvars`, run `terraform apply`, update `~/.ssh/config`.
- **Restrict `allowed_cidr`** to your actual IP (`/32`). If your IP is dynamic, update the variable and run `terraform apply` to refresh the Security Group rule.
