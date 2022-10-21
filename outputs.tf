output "app_url" {
  value = "http://${aws_eip.hashicafe.public_dns}"
}

output "ami_id" {
  value = aws_instance.hashicafe.ami
}
