require 'open3'
require 'colorize'
require 'imake'
require_relative 'awsmgr'

##
## Commander Module
##
## This module contains the commands that imake supports
## i.e. 'imake dump' 'imake create'
##
## To add a new command to imake, define a new module method with parameters that
## map to trollop options. Values will be passed in automatically.
##
module Commander

  ##
  ## MANAGEMENT TOOLSET
  ##

  ## Create a skeleton stack folder
  def self.init argv
    if Dir.exists? argv
      abort ("Error: directory #{argv} already exists. Please delete before running init.")
    end
    FileUtils.mkdir argv
    FileUtils.cp_r "#{File.dirname(__FILE__)}/skeleton", argv
    $config.accounts.each do |name, settings|
      FileUtils.mkdir
    end
    puts "Skeleton stack #{argv} created."
  end

  ## Prep AWS account for imake
  def self.prep account, region
    self.create(IStack.new("#{File.dirname(__FILE__)}/baseline", 'imake Baseline Stack', false), account, region, true)
  end

  ##
  ## DEPLOYMENT TOOLSET
  ##

  ## Create a stack on AWS
  ## The --force option gives it an upsert behavior, where the stack will be updated if it already exists
  ## This is important for dstack's integration
  def self.create(istack, account, region, force)
    aws = AWSManager.new account, region
    aws.with_aws(istack, $config.use_dynamodb) do |cfn_client, cfn_resource, stack, template_url|
      begin
        cfn_resource.create_stack(
          stack_name:   istack.name,
          template_url: template_url,
          capabilities: ['CAPABILITY_IAM'],
          on_failure:   $config.aws_on_failure,
          parameters:   Secrets.as_params(region),
          tags:         $config.tags
        )
      rescue Aws::CloudFormation::Errors::AlreadyExistsException
        puts "Warning: Stack #{istack.name} already exists."
        if force
          puts 'Forcing update...'
          self.update istack, account, region
          exit 0
        else
          puts 'Taking no action. To force an update, run imake with the -f flag.'
          exit 0
        end
      end
      cfn_client.wait_until(:stack_create_complete, stack_name: istack.name) do |w|
        print 'Creating.'
        w.before_attempt do |n|
          print "."
        end
      end
      puts "Successfully created Stack".green
    end
  end


  ## Update the stack on AWS
  def self.update(istack, account, region)
    aws = AWSManager.new account, region
    aws.with_aws(istack, $config.use_dynamodb) do |cfn_client, cfn_resource, stack, template_url|
      raise "Stack #{istack.name} does not exist. Taking no action." unless stack.exists?
      stack.update(
        stack_name:   istack.name,
        template_url: template_url,
        capabilities: ['CAPABILITY_IAM'],
        parameters:   Secrets.as_params(region),
        tags:         $config.tags
      )
      cfn_client.wait_until(:stack_update_complete, stack_name: istack.name) do |w|
        print 'Updating.'
        w.before_attempt do |n|
          print "."
        end
      end
      puts "Successfully updated Stack".green
    end
  end


  ## Delete the stack on AWS
  def self.delete(istack, account, region)
    aws = AWSManager.new account, region
    aws.with_aws(istack, update_dynamodb = false) do |cfn_client, cfn_resource, stack|
      raise "Stack #{istack.name} does not exist. Taking no action." unless stack.exists?
      stack.delete
      cfn_client.wait_until(:stack_delete_complete, stack_name: stack.name) do |w|
        print 'Deleting.'
        w.before_attempt do |n|
          print '.'
        end
      end
      puts "Successfully deleted Stack".red
    end
  end


  ##
  ## DEVELOPMENT TOOLSET
  ##

  ## Test the stack against CloudFormation. This does not test the hooks.
  def self.test(istack, account, region)
    aws = AWSManager.new account, region
    aws.make_stack istack.name
    errors = []
    istack.with_substacks(account, region) do |name, body|
      if body[:stderr].length > 0
        errors.push body[:stderr]
      else
        begin
          aws.upload_and_validate name, body
        rescue Aws::CloudFormation::Errors::ValidationError => error
          errors.unshift "CFn Validation Error in #{name}: #{error.message}"
        end
      end
    end
    errors.each do |errtext|
      puts errtext.colorize(:red)
    end.empty? and begin
      puts "No errors found.".colorize(:green)
    end
  end


  ## Dump the cloudformation output to the console
  def self.dump(istack, account, region, prettyprint, colorize)
    istack.with_substacks(account, region, prettyprint: prettyprint, colorize: colorize, template_bucket: $config.accounts[account]['template_bucket']) do |name, body|
      puts "=========  #{name}  ========="
      puts body[:stdout] if body[:stdout].length > 0
      puts body[:stderr] if body[:stderr].length > 0
    end
  end

  ## Do a diff of the current cloudformation JSON as compared to what was saved with diffmark (see below)
  def self.diff(istack, account, region, colorize)
    self.diffmark(istack, account, region, colorize, outputfile="#{$tmpdir}/new.json")
    puts '< Old | New >'
    puts Open3.popen3("diff #{$tmpdir}/old.json #{$tmpdir}/new.json | colordiff") { |stdin, stdout, stderr, wait_thr| stdout.read + stderr.read }
  end

  ## Store the output of cloudformation to a file for use with the diff command
  def self.diffmark(istack, account, region, colorize, outputfile=nil)
    outputfile ||= "#{$tmpdir}/old.json"
    File.delete outputfile if File.exists? outputfile
    istack.with_substacks(account, region, prettyprint: true, template_bucket: $config.accounts[account]['template_bucket']) do |name, body|
      if body[:stdout] == ''
        String.disable_colorization = false if colorize
        puts body[:stderr].red
        exit 1
      end
      open(outputfile, 'a') do |f|
        f.puts "========================  #{name}  ========================"
        f.puts body[:stdout]
      end
    end
  end

  ## Encrypt the `ENCRYPT[]` blocks of a stack.
  def self.encrypt(istack, account, region)
    print "Encrypting plaintext keys in #{istack.name}"
    errorfound = false
    istack.with_substacks(account, region) do |name, body|
      errorfound = true if body[:stderr].length > 0
      print '.'
    end
    puts "Done."
    if errorfound
      puts 'Warning - a substack did not render correctly, which could lead to unencrypted values in config.'
      puts 'Please fix your stacks and try again.'
    else
      puts 'All keys encrypted.'
    end
  end

end
