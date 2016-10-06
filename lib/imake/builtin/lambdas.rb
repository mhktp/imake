require 'imake'

CloudFormation do
  Description 'Lambda functions'
  AWSTemplateFormatVersion '2010-09-09'

  io = TemplateIO.new(self)

  lambdas.each do |lambda_name, lambda|
    Resource "#{lambda_name}" do
      Type 'AWS::Lambda::Function'
      Property 'Code', {'ZipFile' => Fileman.new.in_folder(lambdas_folder).open(lambda_name).with_runtime(lambda['runtime']).serialize}
      Property 'Handler', 'index.handler'
      Property 'Runtime', lambda['runtime']
      Property 'Timeout', '30'
      Property 'Role', FnGetAtt("LambdaExecutionRole#{lambda['execution_role']}", 'Arn')
    end
    if lambda['output']
      io.output(["#{lambda_name}", 'Arn'])
    end
    if lambda['give_permission_to']
      Resource "ConfigRuleForCalling#{lambda_name}" do
        Type 'AWS::Config::ConfigRule'
        Property 'ConfigRuleName', "ConfigRuleForCalling#{lambda_name}"
        Property 'Scope', {'ComplianceResourceTypes' => ['AWS::IAM::User']}
        Property 'Source', {
          'Owner'            => 'CUSTOM_LAMBDA',
          'SourceDetails'    => [{'EventSource' => 'aws.config',
                                  'MessageType' => 'ConfigurationItemChangeNotification'}],
          'SourceIdentifier' => FnGetAtt(lambda_name, 'Arn')
        }
        DependsOn "#{lambda['give_permission_to'].split('.')[0]}PermissionToCallLambda#{lambda_name}"
      end
      Resource "#{lambda['give_permission_to'].split('.')[0]}PermissionToCallLambda#{lambda_name}" do
        Type 'AWS::Lambda::Permission'
        Property 'FunctionName', FnGetAtt(lambda_name, 'Arn')
        Property 'Action', 'lambda:InvokeFunction'
        Property 'Principal', lambda['give_permission_to']
      end
    end
  end

  lambda_execution_roles.each do |role_name, role|
    Resource "LambdaExecutionRole#{role_name}" do
      Type 'AWS::IAM::Role'
      Property('AssumeRolePolicyDocument', {
        'Statement' => [
          {
            'Action'    => ['sts:AssumeRole'],
            'Effect'    => 'Allow',
            'Principal' => {
              'Service' => ['lambda.amazonaws.com']
            }
          }
        ],
        'Version'   => '2012-10-17'
      })
      Property 'Path', '/'
      Property('Policies', [
        {
          'PolicyDocument' => {
            'Statement' => role,
            'Version'   => '2012-10-17'
          },
          'PolicyName'     => 'root'
        }
      ])
    end
  end

end