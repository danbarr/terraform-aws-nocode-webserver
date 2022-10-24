output "app_url" {
  value = "http://${aws_eip.hashicafe.public_dns}"
}

output "ami_id" {
  value = aws_instance.hashicafe.ami
}

output "product" {
  description = "The product which was randomly selected."
  value       = var.hashi_products[random_integer.product.result].name
}
