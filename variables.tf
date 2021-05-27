##################################################################################
# VARIABLES
##################################################################################

variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "private_key_path" {}
variable "key_name" {}
variable "region" {
  default = "us-east-1"
}

#Configuration variable

variable "network_address_space" {
  type = map(string)
}
variable "instance_size" {
  type = map(string)
}
variable "subnet_count" {
  type = map(number)
}
variable "subnet_size" {
  type = map(number)
}

##################################################################################
# LOCALS
##################################################################################

locals {
  env_name = terraform.workspace
}