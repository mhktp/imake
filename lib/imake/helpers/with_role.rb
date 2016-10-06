require 'aws-sdk'
require 'securerandom'
require 'colorize'
require 'json'

CLIENTS = {
  cloudformation: Aws::CloudFormation::Client,
  ec2:            Aws::EC2::Client,
  ecs:            Aws::ECS::Client,
  ecr:            Aws::ECR::Client,
  dynamodb:       Aws::DynamoDB::Client,
  kms:            Aws::KMS::Client,
  rds:            Aws::RDS::Client,
  route53:        Aws::Route53::Client,
  s3:             Aws::S3::Client,
  autoscaling:    Aws::AutoScaling::Client,
  elb:            Aws::ElasticLoadBalancing::Client,
  lambda:         Aws::Lambda::Client,
  iam:            Aws::IAM::Client,
  elasticache:    Aws::ElastiCache::Client,
  cloudwatch:     Aws::CloudWatch::Client,
  ses:            Aws::SES::Client,
  directconnect:  Aws::DirectConnect::Client
}

def make_mfa(rolename)
  username         = $config.aws_iam_username
  main_acct_num = $config.accounts[$config.primary_account]['account_number']
  if username
    serial_num = "arn:aws:iam::#{main_acct_num}:mfa/#{username}"
    puts "You are attempting to assume #{rolename}, which requires MFA".green
    print "Enter a valid MFA Token: "
    token = gets.chomp
    return serial_num, token
  else
    puts "Error: aws_iam_username is not set in your imake config file.".red
    exit 1
  end
end

def with_profile_creds(client_type, region)
  if has_instance_profile?
    profile_creds = Aws::InstanceProfileCredentials.new
    remote_client = CLIENTS[client_type.to_sym].new(region: region, credentials: profile_creds)
    yield remote_client
  else
    puts "method with_profile_creds can only be run on an EC2 Instance with an InstanceProfile attached"
    exit 1
  end
end


def with_role(account_number, rolename, client_type, region)
  # If we've already assumed a role, then we can't assume another role using those role credentials
  # So use our AWS credentials in order to assume another role
  creds_from_aws_config     = Aws::SharedCredentials.new
  sts_client                = Aws::STS::Client.new(credentials: creds_from_aws_config)
  role_arn                  = "arn:aws:iam::#{account_number}:role/#{iname('Aws::IAM::Role', rolename)}"
  serial_number, token_code = make_mfa(rolename)
  role_credentials          = Aws::AssumeRoleCredentials.new(
                              client: sts_client,
                              region: region,
                              role_arn: role_arn,
                              serial_number: serial_number,
                              token_code: token_code,
                              role_session_name: "remote-account-#{SecureRandom.uuid}"
                            )
  remote_client             = CLIENTS[client_type.to_sym].new(region: region, credentials: role_credentials)
  yield remote_client
end

private

def has_instance_profile?
  info = `curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/iam/info/`
  return false if info.empty?
  begin
    not JSON.parse(info)['InstanceProfileIdont'].empty?
  rescue NoMethodError
    return false
  end
end
