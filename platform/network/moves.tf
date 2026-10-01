moved {
  from = aws_subnet.public_subnet
  to   = aws_subnet.cert_subnet
}

moved {
  from = aws_route_table.public_route_table
  to   = aws_route_table.cert_route_table
}

moved {
  from = aws_route_table_association.public_rt_association
  to   = aws_route_table_association.cert_rt_association
}