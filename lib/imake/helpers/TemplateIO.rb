require 'yaml'
require 'deep_merge'

class TemplateIO
  @@cache_file="#{$tmpdir}/iocache.yaml"


  def initialize(context)
    @context   = context
    @stackname = caller[0].split('/').last.split('.')[0]
    @io        = {params: [], outputs: []}
  end


  def params(param_array)
    param_array.each { |param| self.param(param) }
  end


  def param(param)
    @context.Parameter(param) do
      Type 'String'
    end
    @io[:params].push(param)
    self.save_cache
  end


  def output(param)
    if param.is_a? Array
      @context.Output(param[0]) do
        Value FnGetAtt(param[0], param[1])
      end
      @io[:outputs].push(param[0])
    else
      @context.Output(param) do
        Value Ref(param)
      end
      @io[:outputs].push(param)
    end
    self.save_cache
  end


  def in_baseline_get_output(stackname, outputname, put_self_here)
    self.param(stackname)
    self.param('lookupStackOutputs')
    @context.Resource "#{stackname}Outputs" do
      Type "Custom::#{stackname}Outputs"
      Property 'ServiceToken', Ref('lookupStackOutputs')
      Property 'StackName', Ref(stackname)
      Property 'TimeStamp', Time.now.to_i #ensures that the custom resource is recreated on every stack update
    end
    put_self_here.FnGetAtt("#{stackname}Outputs", outputname)
  end

  alias_method :from_sibling_get_output, :in_baseline_get_output


  def save_cache
    if File.exists? @@cache_file
      temp = YAML::load_file(@@cache_file)
    else
      temp = {}
    end
    temp.deep_merge!({@stackname => @io})
    File.open(@@cache_file, 'w') { |f| f.write YAML::dump(temp) }
  end


  def self.get_cache
    if File.exists?(@@cache_file)
      all_params = YAML::load_file(@@cache_file)
      #File.delete @@cache_file
      return all_params
    end
    return {}
  end
end

#TODO: Make this class automatically provide Refs to outputs from both other substacks (under master), and from pre-existing stacks (see IMStack.rb). It should replace the IMStack class.
# io.get_output_from_stack('networkStack', "VPC#{vpcname}", self)
