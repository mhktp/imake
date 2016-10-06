require 'trollop'
require 'imake/commander'

def cliopts args
  ##
  ## Load up which subcommands are available.
  ##
  ## Commands are defined dynamically as methods under lib/comander.rb.
  ## We query the Commander module for available methods, and ignore builtins
  subcommands = (Commander.methods - Commander.class.methods).collect { |cmd| cmd.to_s }
  ## If a command is the first CLI param, that is our command. Otherwise, we look for it after option parsing.
  opts = { command:  (subcommands.include? ARGV[0]) ? ARGV.shift : nil }
  opts.merge!(Trollop.options do
    banner <<-EOS
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
    EOS
    opt :account, 'Account (prod, nonprod, ...)', default: $config.primary_account
    opt :vars, 'Key=Value pairs to pass into the template', type: :strings, default: []
    opt :tags, 'TagName=Value pairs to pass to CFN create', type: :strings, default: []
    opt :stack, 'Location of stack folder path', default: '.'
    opt :region, 'AWS region to deploy to', default: $config.region
    opt :nameoverride, 'Manually specify a stack name (stacks with -u)', type: :string, default: nil
    opt :uuidadd, 'Adds a `-UUID` to the end of the stack name to keep it unique (stacks with -n)'
    opt :force, 'Forces an update if a stack already exists (upsert)', default: false
    opt :colorize, 'Colorize output'
    opt :prettyprint, 'Pretty-print output'
    stop_on subcommands
  end)
  # Parse vars into a more usable structure
  opts[:vars] = Hash[opts[:vars].map { |varstr| varstr.split('=').map! { |v|
    begin
      result = JSON.parse(v)
    rescue
      result = (v == 'nil') ? nil : v
    end
    result
  } }]

  # Parse tags into a more usable structure
  opts[:tags] = opts[:tags].map { |i| i.split '=' }.map {|i| {key: i[0], value: i[1]}}

  # We save the opts to a temporary cache file
  # When CfnDsl is run it is a separate process, so when cfndsl code does 'require imake', the options are persisted
  $config.update_running_config(opts)

  # We tell ruby to clear the cache when it exits (this code is caught even on errors)
  at_exit do
    $config.clear_running_config
  end

  # If a command was issued at the beginning of the list, use it, otherwise expect a command issued at the end
  # This is required for backwards compatibility with scripts
  opts[:command] ||= ARGV.shift
  unless subcommands.include? opts[:command]
    puts 'Invalid usage.'
    Trollop::educate
    exit 1
  end

  opts
end
