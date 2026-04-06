output "bastion_public_ip" {
  description = "Elastic IP of the bastion host — use this in your ~/.ssh/config"
  value       = aws_eip.bastion.public_ip
}

output "private_server_ip" {
  description = "Private IP of the private server — only reachable from the bastion"
  value       = aws_instance.private.private_ip
}

output "bastion_instance_id" {
  description = "EC2 instance ID of the bastion host"
  value       = aws_instance.bastion.id
}

output "private_instance_id" {
  description = "EC2 instance ID of the private server"
  value       = aws_instance.private.id
}

output "ubuntu_ami_id" {
  description = "AMI ID resolved — useful for auditing which Ubuntu image was deployed"
  value       = data.aws_ami.ubuntu.id
}

output "ssh_config_snippet" {
  description = "Paste this into your ~/.ssh/config to enable ProxyJump access"
  value       = <<-EOT

    Host bastion
        HostName ${aws_eip.bastion.public_ip}
        User ubuntu
        IdentityFile ~/.ssh/bastion_key

    Host private-server
        HostName ${aws_instance.private.private_ip}
        User ubuntu
        IdentityFile ~/.ssh/private_server_key
        ProxyJump bastion

  EOT
}
