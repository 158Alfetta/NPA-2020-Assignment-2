aws_access_key = ""

aws_secret_key = ""

key_name = "vockey"

# Local path to secret key
private_key_path = "/home/devasc/Desktop/vockeyp.pem" 

# subnet size is "newbit number + from base vpc block
subnet_size = {
  Development = 8
  Production = 8
}

network_address_space = {
  Development = "10.0.0.0/16"
  Production = "10.1.0.0/16"
}

instance_size = {
  Development = "t2.small"
  Production = "t2.medium"
}

subnet_count = {
  Development = 2
  Production = 3
}

min_size = {
  Development = 1
  Production = 2
}

desired_capacity = {
  Development = 1
  Production = 2
}

max_size = {
  Development = 2
  Production = 4
}

