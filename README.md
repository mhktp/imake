# imake

__imake__ is a tool to manage AWS infrastructure. At a high level, it combines CloudFormation (managed by [cfndsl](https://github.com/stevenjack/cfndsl)) with Ruby hooks in a __stack__ to act as a scripting engine, and provides a library of helper functions and classes that make working with these tools easier. It also supports standard AWS management practices, such as using IAM roles to manage multiple accounts.  

## Installation

`gem install imake`

## Getting started

The first time you run imake, it will generate a config file at `~/.imake`. Edit this file with the parameters that apply to you:

```yaml
aws_iam_username: <your username for aws>
aws_on_failure: DO_NOTHING
region: us-east-1
primary_account: prod      # This is important when using multiple accounts and roles
use_dynamodb: false        # Store all generated config in an imake table in dynamodb
accounts:
  prod:
    account_number: 123456789012
    template_bucket: imake-resources
    region_map:
      us-east-1:
        domain: us-east-1.compute.internal
        AZs: [ a, b, d ]
        dc: us1
```

Then, you'll need to prep each AWS account for usage with the tool:

```shell
imake prep -a <account>
```

The prep command deploys a single stack in CloudFormation that contains certain features imake requires to run. As of right now, these consist of a few lambdas that are dependencies for some of the helper functions (such as doing stack lookups). It does not deploy anything that you will be consistently charged for (such as an instance).

## Usage

```shell
Usage: imake [options] command

Commands:
  init <name>              Create a skeleton imake stack with a given name
  prep [--account <acct>]  Prep an aws account for use with imake

  create                   Create stack in CloudFormation
  update                   Update stack in CloudFormation
  delete                   Delete stack from CloudFormation

  dump                     Dumps CFN JSON to console
  test                     Validates stack with CfnDsl and CloudFormation
  diffmark                 Saves stack output in a temporary file
  diff                     Diffs current output with diffmark file

  encrypt                  Encrypts plaintext secrets in config files

Options:
  -a, --account=<s>         Account (prod, nonprod, ...) (default: nonprod)
  -v, --vars=<s+>           Key=Value pairs to pass into the template (default: )
  -t, --tags=<s+>           TagName=Value pairs to pass to CFN create (default: )
  -s, --stack=<s>           Location of stack folder path (default: .)
  -r, --region=<s>          AWS region to deploy to (default: us-east-1)
  -n, --nameoverride=<s>    Manually specify a stack name (stacks with -u)
  -u, --uuidadd             Adds a `-UUID` to the end of the stack name to keep it unique (stacks with -n)
  -f, --force               Forces an update if a stack already exists (upsert)
  -c, --colorize            Colorize output
  -p, --prettyprint         Pretty-print output
  -h, --help                Show this message
```

Note that the defaults for `-a` and `-r` are defined in your `~/.imake` file, and these override them only for a single run.

The `-v` option overrides any variables set in your templates configuration (more on that later).


## Infrastructure Management

The concept of this tool is to abstract the CFNDSL language as much as possible so that we can split code (Ruby) and cofiguration (YAML). As a general rule, as much configuration as possible sould be changed using YAML files, with the template files only used for either defining patterns or creating one-off settings. Additionally, things that can't easily be created in CFNDSL can be done in plain ruby via pre- and post- apply hooks.


### Procedure
This tool provides several commands that help when making changes to the configuration.

- `imake test` returns either a success or failure. A success means that the resuling JSON is valid and that it passes validation in both Cfndsl and Cfn.
- `imake dump` dumps the resulting json to the console.
- `imake diffmark` will save the generated JSON to a file to use in a diff.
- `imake diff` will run a diff between the CFN output and what was saved from the last time `imake diffmark` was run.

When modifying the code or configuration, it is good practice to run `diffmark` before making any changes and run `diff` afterwards to make sure that the changes you made are what you intended.


### Stack Structure

```
stackname
|
--- conf                            # This folder contains .yaml configs that apply to all accounts
|   |
|   --- account1 (i.e.: prod)       # These folders contain .yaml configs that apply only to specific accounts
|   --- account2 (i.e.: nonprod)
|   ...
|
--- files
--- hooks
--- lambdas
--- templates
```

### Using stacks

To create a skeleton stack, run:

```shell
imake init <stackname>
```

To check the output of the stack:

```shell
cd <stackname>
imake dump
```
To point it to a different directory:

```shell
imake -s ~/path/to/imake-stacks/baseline dump
```

To suffix the name with a unique id in the format of `mystack-4f82ce1b683ca6af` (useful for deploying multiple copies):

```shell
imake -u -s ~/path/to/mystack dump
```

To specify the name of the stack when deployed to AWS:

```shell
imake -n StackName -s ~/path/to/mystack dump
```


### Setting up an account

When executing imake, an account must be passed as an argument (see above). Examples of accounts are `prod` and `nonprod`, but others can be created.

An account is defined through a set of YAML files in the `conf/<account>` directory. These should be in a hash format, as the top-level items will be available as variables in your hooks and templates. Default parameters for the account, such as which AZs are available, are defined in your `~/.imake` config file. 

Additionally, several variables will be made available to your CfnDsl templates automatically:
```yaml
stack_name                                    # The name of the stack being created
region                                        # The region the template is being applied to
template_bucket                               # The name of the S3 bucket for the template
lambdas_folder                                # The path of the lambdas folder for your stack
files_folder                                  # The path of the files folder for your stack
```

### Stacks and Substacks

When creating a full stack, you can create more than one template. If you choose to do so, **imake** will automatically create a 'master' stack and nest your stacks under it as children.
 

(For best practices on creating new substacks, keep reading.)


### Writing YAML Configs

Each template file responds to certain global-level variables defined in the yaml files. For example, to add a VPC called `MyVPC` to our prod account (more on accounts later), create a new YAML file in the `conf/<account>` directory, called anything you like, and add:

```yaml
vpc_networks:
  MyVPC:
    CIDR: 10.230.0.0/19
    subnetMask: 23
    security_groups: [ ssh, winrm ]
    subnets:
      ill_call_this_one_X: [ IGW ]
      this_one_Y: [ NAT ]
      and_this_one_Z: ~
```

This will:

- Create a VPC called `MyVPC`
- Create three subnets with the name format of `SubnetMyVPCAz<zone><subnet_name>` in each Availablity Zone as defined in `master.yaml::region_map::AZs` (in this example, 9 total)
- Create an Internet Gateway in the VPC (since 
- Attach the `X` zones to the Internet Gateway (one per VPC)
- Attach the `Y` zones to a Nat Gateway (one per AZ)
- Do nothing special to the `Z` zones
- Generate the applicable routes for all of them
- Put all of these resources under the `network` stack, no matter which YAML file it was created in

To learn more about how this translation works, check out the code in `templates/network.rb`.

### Splitting up YAML files

Templates have access to all of the variables in all of the YAML files at the same time. This is done by recursively merging the contents before applying the script. So, let's say we defined the `MyVPC` VPC in `myvpc.yaml`. We can then go ahead and define another VPC called `Monkey` in `monkey.yaml`, and both will appear in the Network stack. Since the YAML files are merged recursively, we can go so far as to add options to pre-defined VPCs. For example, to add a subnet to the `MyVPC` VPC:

```yaml
--first.yaml--
vpc_networks:
  MyVPC:
    CIDR: 10.230.0.0/19
    subnetMask: 23
    subnets:
      ill_call_this_one_X: [ IGW ]
      this_one_Y: [ NAT ]
      and_this_one_Z: ~
```

```yaml
--second.yaml--
vpc_networks:
  MyVPC:
    subnets:
      forgot_this_one: [ IGW ]
```

This will now add a fourth subnet into the `MyVPC` network and connect it to that VPC's Internet Gateway.

### Run-time variables

Any of the variables specified in the config can be overridden at runtime by passing in either strings or JSON objects using the `-v` option. For example, to add a new another subnet to MyVPC at runtime (although this example is not recommended in production):

```shell
imake -v vpc_networks='{"MyVPC":{"subnets":{"another_one":[ "IGW" ]}}}'
```

To pass a string:

```shell
imake -v ip_address=172.16.42.5
```

To delete any created networks in the stack instead, use the `nil` keyword to override the entire hash in YAML with a null value:

```shell
imake -v vpc_networks=nil
```


## Template Development

In `imake`, each template file gets mapped as a substack in CloudFormation. Example:

```ruby
require 'imake'
CloudFormation do
  Description 'Some description that we can understand.'
  AWSTemplateFormatVersion '2010-09-09'

  Resource iname('AWS::EC2::Subnet', subnet_name, az: zone, vpc: vpcname) do
    Type 'AWS::EC2::Subnet'
    Property 'CidrBlock', subnet_cidrs.next_subnet
    Property 'AvailabilityZone', "#{region}#{zone}"
    Property 'VpcId', Ref(iname('AWS::EC2::VPC', vpcname))
    Property 'Tags', [{'Key' => 'Name', 'Value' => iname('AWS::EC2::Subnet', subnet_name, az: zone, vpc: vpcname)}]
  end

  ...
  
end
```

### Helper Functions
The code can then be a combination of plain Ruby and CfnDsl [(see github documentation)](https://github.com/stevenjack/cfndsl), and to take full advantage of ruby imake supports plugins. These plugins can be found under the `lib/imake/helpers` directory. Any files placed into the directory will be automatically loaded into any template with `require 'imake'`. For example, to collect and generate outputs throughout the code in a readable format:

```ruby
require 'imake'
CloudFormation do
  io = TemplateIO.new
  ...
  io.output("name of resource you created")
  ...
end
```


See [lib/imake/helpers/README.md](lib/imake/helpers/README.md) for more info.


### Accessing Variables

Before `imake` calls `cfndsl` to generate CloudFormation JSON out of a template, it merges all of the YAML config files together. Keep that in mind when picking config variable names, as they should be unique so you don't run into collisions. If both the `network` template and `security` template respond to the `security_groups:` token in YAML, then you will get undesirable results, as the configs for both will overlap.

That said, accessing the variables is done via CfnDsl, so top-level keys will be made available as regular variable names in the templates.

### Hooks

Every AWS action on this file has a pre- and post- hook that allows you to run ruby code, which should be placed in the `hooks` directory in your stack. The filenames you can use are:

 - `pre_create.rb`
 - `post_create.rb`
 - `pre_update.rb`
 - `post_update.rb`
 - `pre_delete.rb`
 - `post_delete.rb`

This is an example hook showcasing what you can do:

```ruby
IMakeHook do
  puts 'This is an example pre-create hook. It is there to showcase the variables made available to your hooks.'

  puts cfn_client        # The AWS Client object
  puts cfn_resource      # The Cloudformation Resource object
  puts stack             # The AWS Stack object

  puts @name             # Your stack's name
  puts @dir              #}
  puts @config_folder    #-}
  puts @template_folder  #--} Paths to the folders of your stack
  puts @hooks_folder     #--}
  puts @lambdas_folder   #-}
  puts @files_folder     #}

  puts account       # The AWS account specified (prod, nonprod, ...)
  puts region            # The region used for deployment (us-east-1, ...)

  puts region_map        # they would be passed into CFNDsl

  # Use a hash as your last statement (WIHTOUT the return keyword) to pass variables back into
  # the config used for the templates. These will also be available in your post-* hooks.
  {'foo' => 'bar'}
end

```
Note that stacks can be defined only with hooks - the templates are not necessary.

### Lambdas

Lambda functions should be placed in the `lambdas` directory. The `lambdas.rb` template will strip the file of all line breaks and indentations and upload it to CloudFormation as inline text. Additionaly, a conf file needs to be created with the following parameters:

```yaml
lambdas:
  lookupStackParameters:
    runtime: nodejs
    execution_role: lookupRole
    output: true
    
lambda_execution_roles:
  lookupRole: [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Effect": "Allow",
      "Resource": "arn:aws:logs:*:*:*"
    }, {
      "Action": [
        "cloudformation:DescribeStacks",
        "cloudformation:ListStackResources"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
```

### Adding built-in templates

Certain templates, such as `master.rb` and `lambdas.rb`, are built into the tool. The procedure to create new ones is as follows:
1. Add the template into the `lib/builtin` directory
2. Open up `lib/istack.rb` and modify the `with_substacks` method with any appropriate logic (conditionals, stack additions, and parameter passing through CfnDsl).


### DyanmoDB
When committing your infrastructure to AWS (`create` or `update`), imake will store the full configuration for your stack into DynamoDB in a table named `imake`. You can then query the config at any time using the keys: `{'stack' => <stack name>, 'account' => <prod, staging, ...>}`

## Best Practices

#### General

When writing a template, there are two questions you need to ask:

* Can I get away with a small modification to an existing template to accomplish what I need?
  If so, then go for it. Remember to `diffmark` and `diff` while you are coding (see above) to make sure that you didn't change the output of pre-existing configs when you make the changes.
* If not, does what I need to generate have a discernable pattern I can describe in code? Or should I treat this as a one-off item?
  If you can create a pattern out of this, or believe that this will be a pattern re-used in the future, then you should choose to use variables in YAML files as a state declaration similar to what is described in the networking example above. Otherwise, feel free to use plain CfnDsl to generate a fixed stack.

In either case, remember that if you have any dynamically generated objects, the output should be stable so that items are processed in a consistent order no matter what changes are made. For example, adding a subnet to the network stack should not change the IP addresses of existing subnets.

#### Resource Naming

See the __iname__ helper in [lib/imake/helpers/README.md](lib/imake/helpers/README.md).

#### Passwords

See the __Secrets__ helper in [lib/imake/helpers/README.md](lib/imake/helpers/README.md).

#### Environments

When writing a stack based around an application, you may want to specify which environment you are using (Apps, Staging, Qa, ...). This can be done by using the `-v` option:

```
-v env=Staging
```

Then in your ruby code, to enforce the requirement that this variable is passed in, you can do:

```ruby
require 'imake'

enforce_runtime_var 'env', 'var2', ...
```

And you'll be able to access it just like any other variable in your config:

```ruby
puts env
```
