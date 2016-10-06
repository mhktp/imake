# iname.rb
#
# About:
#  A function to generate the name for a resource, given specific parameters.
#
# Parameters:
#  resource_type                  The CloudFormation type name (i.e.: 'AWS::EC2::SecurityGroupIngress')
#  identifier      (optional)     A user-specified name for a group of resources  (i.e.: 'Qualys', 'TCServer')
#  belongs_to      (optional)     A hash that specifies ownership of the object, useful for generating
#                                   objects using loops. Specified in most specific to least specific order.
#                                   For example, NAT gateways belong to subnets, which can only exist in a single
#                                   AZ, which a VPC can span many of. Therefore this parameter would be -
#                                       subnet: 'Private', az: a, vpc: 'apps'
#
# Notes:
#  All parameters are case insensitive except for resource_type. Output is always in CamelCase.
#
# Examples:
#          Resource iname('AWS::EC2::VPC', 'apps')                              ===> 'VpcApps'
#          Resource iname('AWS::EC2::Subnet', 'Private', az: 'a', vpc: 'apps')  ===> SubnetPrivateAzAVpcApps
#          Resource iname('AWS::EC2::SubnetRouteTableAssociation', subnet: 'Private', az: 'a', vpc: 'apps') do ===> SubnetRouteTableAssociationSubnetPrivateAzAVpcApps
#            Property 'SubnetId', Ref(iname('AWS::EC2::Subnet', 'Private', az: 'a', vpc: 'apps')) ===> Refers to the subnet created previously
#
#          iname('AWS::EC2::VPCPeeringConnection', from: apps, to: mgmt)
#          iname('AWS::EC2::Route', subnet: subnet_name, az: zone, vpc: vpcname, to: vpc['peers_to'])
#
#          Notice how as resources get 'stacked' onto each other, the naming does as well, creating unique identifiers.

def iname(resource_type, identifier=nil, **belongs_to)
  namestring = resource_type.dup.split('::').last.capitalize
  namestring << identifier.capitalize if identifier
  belongs_to.each do |k, v|
    namestring << k.to_s.capitalize
    namestring << v.capitalize if v.length
  end
  namestring
end
