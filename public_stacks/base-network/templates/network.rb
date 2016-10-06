require 'imake'
CloudFormation do
  Description 'Provides a template for creating a standard network configuration that supports NIST-800-53 and NIST-800-171'
  AWSTemplateFormatVersion '2010-09-09'

  io    = TemplateIO.new(self)

  ############################RESOURCES############################

  peers = {} # Create peering connections if there is a subnet route mapping

  vpc_networks.each do |vpcname, vpc|
    #### Create VPC ####
    Resource iname('AWS::EC2::VPC', vpcname) do
      Type 'AWS::EC2::VPC'
      Property 'CidrBlock', vpc['CIDR']
      Property 'InstanceTenancy', 'default'
      Property 'EnableDnsSupport', 'true'
      Property 'EnableDnsHostnames', 'true'
      Property 'Tags', [{'Key' => 'Name', 'Value' => iname('AWS::EC2::VPC', vpcname)}]
    end
    io.output iname('AWS::EC2::VPC', vpcname)

    #### Create Network ACLs ####
    if vpc.key? 'nacl_groups'
      Resource iname('AWS::EC2::NetworkAcl', vpc: vpcname) do
        Type 'AWS::EC2::NetworkAcl'
        Property 'VpcId', Ref(iname('AWS::EC2::VPC', vpcname))
        Property 'Tags', [{'Key' => 'Name', 'Value' => iname('AWS::EC2::VPC', vpcname)}]
      end
      vpc['nacl_groups'].each do |group|
        nacl_groups[group].each do |rulename, ruleprops|
          Resource iname('AWS::EC2::NetworkAclEntry', rulename, vpc: vpcname) do
            Type 'AWS::EC2::NetworkAclEntry'
            Property 'CidrBlock', ruleprops['cidr']
            Property 'Protocol', ruleprops['proto']
            Property 'RuleAction', ruleprops['action']
            Property 'RuleNumber', ruleprops['ruleno']
            Property 'Egress', ruleprops['egress'] || 'False'
            Property 'NetworkAclId', Ref(iname('AWS::EC2::NetworkAcl', vpc: vpcname))
          end
        end
      end
    end

    #### DHCP Options ####
    Resource iname('AWS::EC2::DHCPOptions', vpc: vpcname) do
      Type 'AWS::EC2::DHCPOptions'
      Property 'DomainName', region_map[region]['domain']
      Property 'DomainNameServers', ['AmazonProvidedDNS']
    end
    Resource iname('AWS::EC2::VPCDHCPOptionsAssociation', vpc: vpcname) do
      Type 'AWS::EC2::VPCDHCPOptionsAssociation'
      Property 'VpcId', Ref(iname('AWS::EC2::VPC', vpcname))
      Property 'DhcpOptionsId', Ref(iname('AWS::EC2::DHCPOptions', vpc: vpcname))
    end

    #### VPC Peering ####
    if vpc['peers_to']
      peervpc = vpc_networks[vpc['peers_to']]
      if peervpc and not peers.key? "#{vpcname}#{vpc['peers_to']}" or peers.key? "#{vpc['peers_to']}#{vpcname}"
        #### Two keys are used so that redundant peering connections are not created ####
        peers["#{vpcname}#{vpc['peers_to']}"] = true
        peers["#{vpc['peers_to']}#{vpcname}"] = true
        peeringnames                          = [vpcname, vpc['peers_to']].sort_by(&:downcase)
        #### VPC Peering ####
        Resource iname('AWS::EC2::VPCPeeringConnection', from: peeringnames[0], to: peeringnames[1]) do
          Type 'AWS::EC2::VPCPeeringConnection'
          DependsOn [iname('AWS::EC2::VPC', peeringnames[0]), iname('AWS::EC2::VPC', peeringnames[1])]
          Property 'VpcId', Ref(iname('AWS::EC2::VPC', peeringnames[0]))
          Property 'PeerVpcId', Ref(iname('AWS::EC2::VPC', peeringnames[1]))
          Property 'Tags', [{'Key' => 'Name', 'Value' => iname('AWS::EC2::VPCPeeringConnection', from: peeringnames[0], to: peeringnames[1])}]
        end
        vpc['subnets'].each do |subnet_name, opts|
          region_map[region]['AZs'].each do |zone|
            Resource iname('AWS::EC2::Route', subnet: subnet_name, az: zone, vpc: vpcname, to: vpc['peers_to']) do
              Type 'AWS::EC2::Route'
              Property 'RouteTableId', Ref(iname('AWS::EC2::RouteTable', subnet: subnet_name, az: zone, vpc: vpcname))
              Property 'DestinationCidrBlock', FnGetAtt(iname('AWS::EC2::VPC', vpc['peers_to']), 'CidrBlock')
              Property 'VpcPeeringConnectionId', Ref(iname('AWS::EC2::VPCPeeringConnection', from: peeringnames[0], to: peeringnames[1]))
            end
          end
          peervpc['subnets'].each do |peer_subnet_name, peer_subnet_opts|
            region_map[region]['AZs'].each do |zone|
              Resource iname('AWS::EC2::Route', subnet: subnet_name, az: zone, vpc: vpc['peers_to'], to: vpcname) do
                Type 'AWS::EC2::Route'
                Property 'RouteTableId', Ref(iname('AWS::EC2::RouteTable', subnet: subnet_name, az: zone, vpc: vpc['peers_to']))
                Property 'DestinationCidrBlock', FnGetAtt(iname('AWS::EC2::VPC', vpcname), 'CidrBlock')
                Property 'VpcPeeringConnectionId', Ref(iname('AWS::EC2::VPCPeeringConnection', from: peeringnames[0], to: peeringnames[1]))
              end
            end
          end
        end
      end
    end

    #### Create Subnets and Associated Objects ####
    nat_gateways = []
    if vpc.key? 'subnets'
      igwname      = nil # Keep track of the IGW in this VPC, if ever created
      subnet_cidrs = SubnetAddress.new(vpc['CIDR'], vpc['subnetMask'], region_map[region].length * vpc['subnets'].length)

      vpc['subnets'].each do |subnet_name, opts|
        region_map[region]['AZs'].each do |zone|

          #### Create Subnet ####
          Resource iname('AWS::EC2::Subnet', subnet_name, az: zone, vpc: vpcname) do
            Type 'AWS::EC2::Subnet'
            Property 'CidrBlock', subnet_cidrs.next_subnet
            Property 'AvailabilityZone', "#{region}#{zone}"
            Property 'VpcId', Ref(iname('AWS::EC2::VPC', vpcname))
            Property 'MapPublicIpOnLaunch', true if opts.include? 'IGW'
            Property 'Tags', [{'Key' => 'Name', 'Value' => iname('AWS::EC2::Subnet', subnet_name, az: zone, vpc: vpcname)}]
          end
          io.output iname('AWS::EC2::Subnet', subnet_name, az: zone, vpc: vpcname)
          #### Create Route Table ####
          Resource iname('AWS::EC2::RouteTable', subnet: subnet_name, az: zone, vpc: vpcname) do
            Type 'AWS::EC2::RouteTable'
            Property 'VpcId', Ref(iname('AWS::EC2::VPC', vpcname))
            Property 'Tags', [{'Key' => 'Name', 'Value' => iname('AWS::EC2::RouteTable', subnet: subnet_name, az: zone, vpc: vpcname)}]
          end
          io.output iname('AWS::EC2::RouteTable', subnet: subnet_name, az: zone, vpc: vpcname)
          #### Associate with Subnet ####
          Resource iname('AWS::EC2::SubnetRouteTableAssociation', subnet: subnet_name, az: zone, vpc: vpcname) do
            Type 'AWS::EC2::SubnetRouteTableAssociation'
            Property 'RouteTableId', Ref(iname('AWS::EC2::RouteTable', subnet: subnet_name, az: zone, vpc: vpcname))
            Property 'SubnetId', Ref(iname('AWS::EC2::Subnet', subnet_name, az: zone, vpc: vpcname))
          end
          #### Associate NACLs ####
          if vpc.key? 'nacl_groups'
            Resource iname('AWS::EC2::SubnetNetworkAclAssociation', subnet: subnet_name, az: zone, vpc: vpcname) do
              Type 'AWS::EC2::SubnetNetworkAclAssociation'
              Property 'NetworkAclId', Ref(iname('AWS::EC2::NetworkAcl', vpc: vpcname))
              Property 'SubnetId', Ref(iname('AWS::EC2::Subnet', subnet_name, az: zone, vpc: vpcname))
            end
          end

          opts.each do |opt|
            if opt == 'IGW'
              unless igwname
                Resource iname('AWS::EC2::InternetGateway', vpc: vpcname) do
                  Type 'AWS::EC2::InternetGateway'
                  Property 'Tags', [{'Key' => 'Name', 'Value' => iname('AWS::EC2::InternetGateway', vpc: vpcname)}]
                end
                #### Attach to VPC ####
                Resource iname('AWS::EC2::VPCGatewayAttachment', vpc: vpcname) do
                  Type 'AWS::EC2::VPCGatewayAttachment'
                  DependsOn iname('AWS::EC2::InternetGateway', vpc: vpcname)
                  Property 'VpcId', Ref(iname('AWS::EC2::VPC', vpcname))
                  Property 'InternetGatewayId', Ref(iname('AWS::EC2::InternetGateway', vpc: vpcname))
                end
                #### Save Name so we don't recreate the resource ####
                igwname = iname('AWS::EC2::InternetGateway', vpc: vpcname)
              end
              #### Route to IGW ####
              Resource iname('AWS::EC2::Route', subnet: subnet_name, az: zone, vpc: vpcname, to: 'IGW') do
                Type 'AWS::EC2::Route'
                Property 'DestinationCidrBlock', '0.0.0.0/0'
                Property 'RouteTableId', Ref(iname('AWS::EC2::RouteTable', subnet: subnet_name, az: zone, vpc: vpcname))
                Property 'GatewayId', Ref(igwname)
              end
            end
            if opt == 'NAT'
              unless nat_gateways.include? iname('AWS::EC2::NatGateway', az: zone, vpc: vpcname)
                #### Elastic IP for Gateway ####
                Resource iname('AWS::EC2::EIP', 'NatGateway', az: zone, vpc: vpcname) do
                  Type 'AWS::EC2::EIP'
                  Property 'Domain', 'vpc'
                end
                #### Gateway ####
                Resource iname('AWS::EC2::NatGateway', az: zone, vpc: vpcname) do
                  Type 'AWS::EC2::NatGateway'
                  Property 'SubnetId', Ref(iname('AWS::EC2::Subnet', subnet_name, az: zone, vpc: vpcname))
                  Property 'AllocationId', FnGetAtt(iname('AWS::EC2::EIP', 'NatGateway', az: zone, vpc: vpcname), 'AllocationId')
                end
              end
              #### Route to NAT Gateway ####
              Resource iname('AWS::EC2::Route', subnet: subnet_name, az: zone, vpc: vpcname, to: 'NATGateway') do
                Type 'AWS::EC2::Route'
                Property 'DestinationCidrBlock', '0.0.0.0/0'
                Property 'RouteTableId', Ref(iname('AWS::EC2::RouteTable', subnet: subnet_name, az: zone, vpc: vpcname))
                Property 'NatGatewayId', Ref(iname('AWS::EC2::NatGateway', az: zone, vpc: vpcname))
              end unless opts.include? 'IGW'
            end
          end if opts # Opts
        end # Zones
      end # Subnets
    end # if subnets

    #### Baseline Security Group ####
    # Automatically create an empty baseline security group
    # in each VPC. This is for use by 'baseline' tools
    # common to all instances (monitoring, security scanning, etc).
    # It will have rules added by other templates and/or stacks.
    Resource iname('AWS::EC2::SecurityGroup', 'Baseline', vpc: vpcname) do
      Type 'AWS::EC2::SecurityGroup'
      Property 'GroupDescription', iname('AWS::EC2::SecurityGroup', 'Baseline', vpc: vpcname)
      Property 'VpcId', Ref(iname('AWS::EC2::VPC', vpcname))
      Property 'Tags', [{'Key' => 'Name', 'Value' => iname('AWS::EC2::SecurityGroup', 'Baseline', vpc: vpcname)}]
    end
    io.output iname('AWS::EC2::SecurityGroup', 'Baseline', vpc: vpcname)

    #### Security Groups ####
    if vpc.key? 'security_groups'
      vpc['security_groups'].each do |secgroup_name|
        Resource iname('AWS::EC2::SecurityGroup', secgroup_name, vpc: vpcname) do
          Type 'AWS::EC2::SecurityGroup'
          Property 'GroupDescription', iname('AWS::EC2::SecurityGroup', secgroup_name, vpc: vpcname)
          Property 'VpcId', Ref(iname('AWS::EC2::VPC', vpcname))
          Property 'Tags', [{'Key' => 'Name', 'Value' => iname('AWS::EC2::SecurityGroup', secgroup_name, vpc: vpcname)}]
        end
        io.output iname('AWS::EC2::SecurityGroup', secgroup_name, vpc: vpcname)
      end
    end

  end if defined? vpc_networks # VPCs

  #### Network Interfaces ####
  if defined? network_interfaces
    network_interfaces.each do |name, nic|
      subnetvpc, subnetname = nic['subnet'].split('.')
      sgvpc, sgname         = nic['security_group'].split('.')
      Resource iname('AWS::EC2::NetworkInterface', name) do
        Type 'AWS::EC2::NetworkInterface'
        Property 'SubnetId', Ref(iname('AWS::EC2::Subnet', subnetname, az: region_map[region]['AZs'][0], vpc: subnetvpc))
        Property 'GroupSet', [Ref(iname('AWS::EC2::SecurityGroup', sgname, vpc: sgvpc))]
        Property 'Description', ''
        Property 'Tags', [{'Key' => 'Name', 'Value' => iname('AWS::EC2::NetworkInterface', name)}]
      end
      io.output iname('AWS::EC2::NetworkInterface', name)
      Output(iname('AWS::EC2::NetworkInterface', name, property: 'PrimaryPrivateIpAddress')) do
        Value FnGetAtt(iname('AWS::EC2::NetworkInterface', name), 'PrimaryPrivateIpAddress')
      end
    end
  end
end
