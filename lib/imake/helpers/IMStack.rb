require 'aws-sdk'

class IMStack
  def initialize(stackname, region, cfn_client=nil)
    @cfn_client    = cfn_client || Aws::CloudFormation::Client.new(region: region)
    @cfn_resource  = Aws::CloudFormation::Resource.new client: @cfn_client
    @stack         = @cfn_resource.stack(stackname)
    @cached_stacks = {}
  end

  attr_reader :stack


  def with_substack(name)
    unless @cached_stacks.key? name
      @cached_stacks[name] = IMStack.new(self.physical_id(name), $config.region)
    end
    @cached_stacks[name]
  end


  def physical_id(logical_id = nil)
    if logical_id
      @stack.resource_summaries.find { |rs| rs.logical_id == logical_id }.physical_resource_id
    else
      @stack.stack_id
    end
  end


  def get_output(output_key)
    @stack.outputs.find { |o| o.output_key == output_key }.output_value
  end


  def get_vpc_subnets_by_type(vpc, subnet_type)
    #get all VPC subnets of a particular type (ex. all Private Subnets in the Apps VPC)
    #returns array of subnet ids
    match = /^Subnet#{Regexp.quote(subnet_type).capitalize}Az[a-zA-Z]Vpc#{Regexp.quote(vpc).capitalize}$/ #Should we use the name factory instead of a regex?
    @stack.outputs.map { |o| o.output_value if o.output_key =~ match }.compact
  end
end #Stack