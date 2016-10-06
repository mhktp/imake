require 'netaddr'

class SubnetAddress
  def initialize(parent_cidr, child_mask, no_subnets_needed)
    @parent_cidr   = NetAddr::CIDR.create parent_cidr
    @child_subnets = @parent_cidr.subnet :Bits => child_mask
    if @child_subnets.length < no_subnets_needed
      raise "Subnet mask #{child_mask} is too large for the VPC with CIDR #{parent_cidr}. Can't create enough subnets to fill all selected zones."
    end
    @subnet_ptr = -1
  end


  def next_subnet
    @subnet_ptr += 1
    @child_subnets[@subnet_ptr]
  end
end
