require 'imake'
CloudFormation do
  Description 'Add security group rules to the SGs created in the network stack.'
  AWSTemplateFormatVersion '2010-09-09'

  io = TemplateIO.new(self)

  ############################RESOURCES############################

  vpc_networks.each do |vpcname, vpc|

    #### Security Groups ####
    if vpc.key? 'security_groups'
      vpc['security_groups'].each do |secgroup_name|

        security_groups[secgroup_name] = {secgroup_name => security_groups[secgroup_name]} if security_groups[secgroup_name].is_a? String
        if security_groups[secgroup_name].key? 'services' and security_groups[secgroup_name].key? 'cidrs'
          full_map                       = security_groups[secgroup_name]['cidrs'].map do |cidrname, cidrblock|
            security_groups[secgroup_name]['services'].map { |srvname, srvdetails| ["#{cidrname}#{srvname}", "#{srvdetails}|#{cidrblock}"] }.to_h
          end.reduce Hash.new, :merge
          security_groups[secgroup_name] = full_map
        end
        security_groups[secgroup_name].each do |rulename, ruleprops|
          proto, fromport, toport, optional_cidr = ruleprops.split('|')
          next unless proto

          if optional_cidr
            cidrip, cidrmask = optional_cidr.split('/')
            if cidrip and cidrmask
              cidrip = "#{cidrip}/#{cidrmask}"
            elsif optional_cidr.start_with?('NIC')
              cidrip = FnJoin('', [io.in_baseline_get_output('networkStack', iname('AWS::EC2::NetworkInterface', optional_cidr.split('.')[1], property: 'PrimaryPrivateIpAddress'), self), '/32'])
            end
          else
            cidrip = vpc['CIDR']
          end

          Resource iname('AWS::EC2::SecurityGroupIngress', rulename, securitygroup: secgroup_name, vpc: vpcname) do
            Type 'AWS::EC2::SecurityGroupIngress'
            Property 'CidrIp', cidrip
            Property 'FromPort', fromport
            Property 'ToPort', toport
            Property 'IpProtocol', proto
            Property 'GroupId', io.in_baseline_get_output('networkStack', iname('AWS::EC2::SecurityGroup', secgroup_name, vpc: vpcname), self)
          end
        end
      end
    end
  end if defined? vpc_networks # VPC

end
