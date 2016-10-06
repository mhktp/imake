require 'imake'
CloudFormation do
  Description 'Provides VPN connectivity to AWS.'
  AWSTemplateFormatVersion '2010-09-09'

  io = TemplateIO.new(self)

  vpcs_with_gateways = {}
  customer_gateways.each do |gwname, gateway|
    Resource iname('AWS::ECS::CustomerGateway', gwname) do
      Type 'AWS::EC2::CustomerGateway'
      Property 'Type', 'ipsec.1'
      Property 'BgpAsn', gateway['bgp_asn']
      Property 'IpAddress', gateway['peer_ip']
      Property 'Tags', [{'Key' => 'Name', 'Value' => iname('AWS::ECS::CustomerGateway', gwname)}]
    end

    if gateway.key? 'connects_to_vpcs'
      gateway['connects_to_vpcs'].each do |vpcname|
        ### Create a gateway in the VPC if it doesn't already exist
        unless vpcs_with_gateways.has_key? vpcname
          vpcs_with_gateways[vpcname] = iname('AWS::EC2::VPNGateway', vpcname)
          Resource iname('AWS::EC2::VPNGateway', vpcname) do
            Type 'AWS::EC2::VPNGateway'
            Property 'Type', 'ipsec.1'
            Property 'Tags', [{'Key' => 'Name', 'Value' => iname('AWS::EC2::VPNGateway', vpcname)}]
          end
           Resource iname('AWS::EC2::VPCGatewayAttachment', vpcname) do
            Type 'AWS::EC2::VPCGatewayAttachment'
            Property 'VpcId', io.in_baseline_get_output('networkStack', iname('AWS::EC2::VPC', vpcname), self)
            Property 'VpnGatewayId', Ref(iname('AWS::EC2::VPNGateway', vpcname))
          end
        end

        ### Conect to the VPC
        Resource iname("AWS::EC2::VPNConnection", gwname, vpc: vpcname) do
          Type 'AWS::EC2::VPNConnection'
          Property 'Type', 'ipsec.1'
          Property 'StaticRoutesOnly', 'false'
          Property 'CustomerGatewayId', Ref(iname('AWS::ECS::CustomerGateway', gwname))
          Property 'VpnGatewayId', Ref(iname('AWS::EC2::VPNGateway', vpcname))
          Property 'Tags', [{'Key' => 'Name', 'Value' => iname("AWS::EC2::VPNConnection", gwname, vpc: vpcname)}]
        end

        ### Set routes in that VPC's subnets
        vpc_networks[vpcname]['subnets'].each do |subnet_name, opts|
          region_map[region]['AZs'].each do |zone|
            ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16'].each do |cidr|
              Resource iname('AWS::EC2::Route', cidr.split('.')[0], subnet: subnet_name, az: zone, vpc: vpcname) do
                Type 'AWS::EC2::Route'
                DependsOn iname('AWS::EC2::VPCGatewayAttachment', vpcname)
                Property 'RouteTableId', io.in_baseline_get_output('networkStack', iname('AWS::EC2::RouteTable', subnet: subnet_name, az: zone, vpc: vpcname), self)
                Property 'DestinationCidrBlock', cidr
                Property 'GatewayId', Ref(iname('AWS::EC2::VPNGateway', vpcname))
              end
            end
          end
        end
      end
    end
  end

end
