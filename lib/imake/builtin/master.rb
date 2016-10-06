require 'imake'
require 'open3'
require 'yaml'
require 'deep_merge'
CloudFormation do
  Description 'Master stack for loading all other stacks.'
  AWSTemplateFormatVersion '2010-09-09'

  io = TemplateIO.new(self)
  baseline = Aws::CloudFormation::Stack.new(name: 'baseline', region: $config.region)


  stacks = YAML.load_file("#{$tmpdir}/validstacks.yaml").map { |stack| File.basename(stack, '.rb') }
  File.delete("#{$tmpdir}/validstacks.yaml")

  # Possible parameters to pass
  parameters = {}
  stacks.each do |name|
    parameters["#{name}Stack"] = Ref("#{name}Stack")
  end
  if baseline.exists?
    Aws::CloudFormation::Stack.new(name: baseline.resource('lambdasStack').physical_resource_id, region: $config.region).outputs.each do |o|
      parameters[o.output_key] = o.output_value
    end
  end
  if defined? lambdas and defined? lambdas_folder and Dir.exists? lambdas_folder
    stacks.push 'lambdas'
    lambdas.each do |k, v|
      if v.key? 'output' and v['output']
        parameters[k] = FnGetAtt('lambdasStack', "Outputs.#{k}")
      end
    end
  end

  # Get hashmap of parameters needed by stacks
  all_io = TemplateIO.get_cache

  passthrough = {}
  Secrets.all_secrets.each do |stackname, secrethash|
    passthrough[stackname] = secrethash.keys
    secrethash.keys.each do |param|
      Parameter param do
        Type 'String'
        NoEcho 'True'
      end
    end
  end

  stacks.each do |name|
    final_params = {}
    if all_io.key? name
      final_params.deep_merge! parameters.select { |k, v| all_io[name][:params].include? k }
    end
    if passthrough.key? name
      passthrough[name].each { |par| final_params[par] = Ref(par) } # Deep_merge seems to break on the Ref statement
    end
    Resource "#{name}Stack" do
      Type 'AWS::CloudFormation::Stack'
      Property 'TemplateURL', "https://s3.amazonaws.com/#{template_bucket}/cfn_templates/#{stack_name}/#{name}.json"
      Property 'TimeoutInMinutes', '60'
      Property('Parameters', final_params) if final_params.size > 0
    end
    io.output "#{name}Stack"
  end
end
