
##################################################################################
# OUTPUT
##################################################################################

output "aws_lb_public_dns" {
  value = aws_elb.elastic-lb.dns_name
}