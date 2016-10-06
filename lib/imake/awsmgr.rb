require 'aws-sdk'
require 'yaml'
require 'colorize'

## AWSManager handles all communication between imake and AWS
class AWSManager
  def initialize(acct, region)
    @cfn_client   = Aws::CloudFormation::Client.new(region: region)
    @cfn_resource = Aws::CloudFormation::Resource.new client: @cfn_client
    @region       = region
    @acct         = acct
    @bucket       = $config.accounts[acct]['template_bucket']
  end


  def make_stack(stack_name)
    @stack = Aws::CloudFormation::Stack.new name: stack_name, region: @region
  end


  # This is the brains of the 'test' command. It is also run before any CrUD operation (see the with_aws method)
  def upload_and_validate(name, body)
    s3object = Aws::S3::Object.new(region: @region, bucket_name: @bucket, key: "cfn_templates/#{@stack.name}/#{name}.json")
    s3object.put(body: body[:stdout])
    if body[:stderr].length > 0
      puts "There is an error in your #{name} template. Will not make changes on Amazon."
      puts body[:stderr].red
      exit 1
    end
    print "Validating substack #{name}..."
    begin
      @cfn_client.validate_template({template_url: "https://s3.amazonaws.com/#{@bucket}/cfn_templates/#{@stack.name}/#{name}.json"})
    rescue Aws::CloudFormation::Errors::ValidationError => error
      String.disable_colorization = false
      puts "Failed!".colorize(:red)
      String.disable_colorization = true
      raise error
    else
      String.disable_colorization = false
      puts "Done".colorize(:green)
      String.disable_colorization = true
    end
  end


  ## This method performs the application of a stack. It will select and run the applicable hooks before and after deployment, and yeild to a block
  ## To determine exactly what to do with cloudformation. It is the 'brains' of the create, update and delete methods
  def with_aws(stack, update_dynamodb = false)
    action = caller[0].split('`')[1].chomp("'")
    self.make_stack(stack.name)
    stack.run_hook("pre_#{action}", @acct, @region, :cfn_client => @cfn_client, :cfn_resource => @cfn_resource, :stack => @stack)

    if stack.has_substacks?
      puts "Performing a '#{action}' on stack '#{stack.name}' in AWS CloudFormation..."
      stack.with_substacks(@acct, @region, template_bucket: @bucket) do |name, body|
        self.upload_and_validate(name, body)
      end
      yield @cfn_client, @cfn_resource, @stack, "https://s3.amazonaws.com/#{@bucket}/cfn_templates/#{@stack.name}/#{stack.maintarget}.json"
    end

    stack.run_hook("post_#{action}", @acct, @region, :cfn_client => @cfn_client, :cfn_resource => @cfn_resource, :stack => @stack)
    self.update_dynamo_with_config(stack, @region) if update_dynamodb
    puts "Done updating AWS CloudFormation. See the CloudFormation console for status."
  end

  ## This stores any run cloudformation in DynamoDB
  def update_dynamo_with_config(stack, region)
    begin
      client       = Aws::DynamoDB::Client.new(region: region)
      dynamodb     = Aws::DynamoDB::Resource.new(client: client)
      dynamo_table = dynamodb.table('imake')

      item        = {'stack' => stack.name, 'environment' => @acct}
      config_hash = {item: item.merge(stack.fullconfig(@acct))}
      dynamo_table.put_item(config_hash)
    rescue
      STDERR.puts "Failed updating DyanmoDB. Your changes may have been applied but the config was not saved in AWS."
    end
  end
end
