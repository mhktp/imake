# imake helpers

The __imake helpers__ is a code library made available to __imake stacks__ to provide shortcuts and other functions to make infrastructure code development easier.

## General Usage
Both templates and hooks in an __imake stack__ can use the helper library (though some helpers can be used only on one or the other). To bring the helpers into your code, do:

```ruby
require 'imake'
```

This makes all of the helpers available to your code.

## Helper List

1. iname
2. TemplateIO
3. Secrets
4. IMStack
5. Fileman
6. with_role


## iname
__iname__ is a function that provides a standardized way of naming resources in AWS, ensuring that your resource names remain unique across the entire infrastructure.

```ruby
def iname(resource_type, identifier=nil, **belongs_to)
```

### Parameters

* `resource_type`: The CloudFormation type name (i.e.: 'AWS::EC2::SecurityGroupIngress')
* `identifier` (optional): A user-specified name for a group of resources  (i.e.: 'Qualys', 'TCServer')
* `belongs_to`: A hash that specifies ownership of the object, useful for generating objects using loops. Specified in most specific to least specific order. For example, NAT gateways belong to subnets, which can only exist in a single AZ, which a VPC can span many of. Therefore this parameter would be - `subnet: 'Private', az: a, vpc: 'apps'`

Note that all parameters are case insensitive except for resource_type. Output is always in CamelCase.

### Usage

* `Resource iname('AWS::EC2::VPC', 'apps')`                              ===> `'VpcApps'`
* `Resource iname('AWS::EC2::Subnet', 'Private', az: 'a', vpc: 'apps')`  ===> `SubnetPrivateAzAVpcApps`
* `Resource iname('AWS::EC2::SubnetRouteTableAssociation', subnet: 'Private', az: 'a', vpc: 'apps')` ===> `SubnetRouteTableAssociationSubnetPrivateAzAVpcApps`
* `Property 'SubnetId', Ref(iname('AWS::EC2::Subnet', 'Private', az: 'a', vpc: 'apps'))` ===> Refers to the subnet created previously

Notice how as resources get 'stacked' onto each other, the naming does as well, creating unique identifiers.

* `iname('AWS::EC2::VPCPeeringConnection', from: apps, to: mgmt)`
* `iname('AWS::EC2::Route', subnet: subnet_name, az: zone, vpc: vpcname, to: vpc['peers_to'])`

Iname should also be used for the "Name" tag.

```ruby
Property 'Tags', [{'Key' => 'Name', 'Value' => iname('AWS::EC2::SecurityGroup', 'Baseline', vpc: vpcname)}]
```

## TemplateIO

TemplateIO is a class that abstracts the most common design patterns for CloudFormation Parameters and Outputs away from the user. Additionally, it serves as an IPC channel between created stacks and the master stack to pass parameters back and forth.

### Usage

Instantiate an object, passing in the parent CloudFormation object created with CfnDsl

```ruby
io = TemplateIO.new(self)
```

You can now specify parameters for your template:

```ruby
io.params ['networkStack', 'accessStack']
io.param 'lambdasStack'

=>

Parameter('networkStack') do
  Type 'String'
end
...
```

As well as outputs:

```ruby
io.output iname('AWS::EC2::VPC', vpcname)

=>

Output(iname('AWS::EC2::VPC', vpcname)) do
  Value Ref(param)
end
      
```

```ruby
io.output [iname('AWS::RDS::DBInstance', "#{vpc_name}Rds"), 'Endpoint.Address']

Output(iname('AWS::RDS::DBInstance', "#{vpc_name}Rds")) do
  Value FnGetAtt(iname('AWS::RDS::DBInstance', "#{vpc_name}Rds"), 'Endpoint.Address')
end

```

Note that parameters, since made mostly unnecessary due to the way that __imake__ handles configuration, are mainly used to bring in references to sister stacks - and these references will automatically get passed in by the master stack. (See the example above)

Furthermore, when developing on baseline, there is a baseline-specific function that allows looking up specific resources in sister stacks _(for looking up resources in pre-existing stacks, see IMStack)_

```ruby
Property 'VpcId', io.in_baseline_get_output('networkStack', iname('AWS::EC2::VPC', vpc_name), self)
```

This will automatically create the `Parameter`, `CustomResource`, `Ref` pattern needed in the template to do the lookup.

## Secrets

Passwords, if handled improperly, can be a major security risk. To make sure that they don't get committed to the repo in plaintext, uploaded to S3, and become visible in cloudformation, they should be managed with our `Secrets` helper.

You will need your team's KMS key name to use secrets.

```yaml
# conf.yaml #
db_password: ENCRYPT[<kms_keyname>||YourPasswordGoesHere1234]
```

```ruby
# template.rb #
secrets = Secrets.new(self, binding)
Resource iname('AWS::RDS::DBInstance', 'MyDB') do
	Property 'MasterUserPassword', secrets.hide_parameter(db_password)
```

The first time you run your template, __imake__ will automatically encrypt the value for you and replace it in your config file with an encrypted hash:

```yaml
# conf.yaml #
db_password: DECRYPT[<kms_keyname>||GrOdUUmBE4SgmmCHPQWVxKbAQEBAgB4WvNx8...]
```

Also note that this is a two-step process. The `ENCRYPT` tag in your variable enables encryption while the `hide_parameter()` method makes it invisible in AWS. You can hide variables without encrypting them, but the reverse is not also true.

__WARNING: MAKE SURE YOU ENCRYPT ALL SENSITIVE TEXT VALUES BEFORE COMMITTING YOUR WORK TO GIT!!!!!__


## IMStack

To look up resources in other, already-deployed stacks, use the __IMStack__ helper.


```ruby
b_stack = IMStack.new 'baseline', region
lookup_stack_outputs   = b_stack.with_substack('lambdasStack').get_output('lookupStackOutputs')
network_stack          = b_stack.with_substack('networkStack').physical_id

Resource 'NetworkOutputs' do
Type 'Custom::NetworkOutputs'
Property 'StackName', network_stack
Property 'ServiceToken', lookup_stack_outputs
end

FnGetAtt('NetworkOutputs', iname('AWS::EC2::NetworkInterface', group_name))
```

## Fileman
Fileman is used to provide shortcuts when accessing files in Cfn templates. It allows operations on both plaintext files as well as ERB templates, and provides wrappers as shortcuts for CfnDsl. An example use case is providing cloud-init scripts for EC2 instances.


ERB as text:

```
Fileman.new("#{files_folder}/somefile.erb").as_template(binding)
```

Serialized text (javascript is automatically minified using the __Uglifier__ gem):

```
Fileman.new('somefile.txt').serialize
```

Some CloudFormation functions will fail if you don't use `FnJoin` to create an object out of a string. In those cases:

```
Fileman.new('somefile.txt').arrayified_join

=>

{'Fn::Join' => ["\n", line1, line2, ...]}
```

You can also apply it to templates:

```
Property 'UserData', Fileman.new.('consul_userdata.erb').as_template(binding).to_cfnarray
```

And do it for cloud init shell scripts for instances:

```
"Configure" => {
  "commands" =>  Fileman.new('configure_server.erb').as_template(binding).to_cmdlist
}
```

## with_role

At times, you will need a single script to run commands in multiple AWS accounts in a single run - for example, when setting up VPC Peering. It is expected that permissions have been set up to allow your IAM user/group to assume the role in the remote account. If you receive a permissions error when attempting to assume a role, contact the CloudOps team with details.

To assume a role in an imake hook (for example) you can use the `with_role` helper:

```ruby
nonprod_acct_num  = '061851502621'
nonprod_role_name = 'sysadmin'
IMakeHook do
  with_role(nonprod_acct_num, nonprod_role_name, 's3', 'us-east-1') do |nonprod_s3_client|
    nonprod_s3_client.create_bucket({
      bucket_name: ...
    })
  end
end
```

Current roles that can be assumed are:
- Sysadmin: Allows all actions except IAM
- IAMAdmin: Allows only IAM actions
- ReadOnlyAdmin: Allows read only access to all AWS services

Note: If using this helper from within a CfnDsl template, the resulting CloudFormation json is not affected.

See the `with_role.rb` file for a list of supported clients.

