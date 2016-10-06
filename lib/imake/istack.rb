require 'deep_merge'
require 'colorize'
require 'open3'
require 'json'
require 'securerandom'
require 'shellwords'


class IStack
  def initialize(stack_identifier, name_override, add_uuid)
    @dir              = File.expand_path(stack_identifier)
    @name             = @dir.split('/').last
    @name             = name_override if name_override
    @name             = "#{@name}-#{SecureRandom.hex[0...16]}" if add_uuid
    @config_folder    = "#{@dir}/conf"
    @template_folder  = "#{@dir}/templates"
    @hooks_folder     = "#{@dir}/hooks"
    @lambdas_folder   = "#{@dir}/lambdas"
    @files_folder     = "#{@dir}/files"
    @full_config_file = "#{$tmpdir}/fullconfig.yaml"
    @maintarget       = nil
    @hooks_vars       = nil
  end


  attr_reader :name, :maintarget


  def has_substacks?
    Dir.exists?(@template_folder)
  end


  def fullconfig(acct, moreopts = {})
    @fullconfig = {}

    # First pull in the local config
    @fullconfig.deep_merge! $config.accounts[$config.account]

    # Then the template's global config
    Dir.glob("#{@config_folder}/#{acct}/*.{yaml,yml,json}").sort.each do |configfile|
      @fullconfig.deep_merge! YAML::load_file(configfile)
    end

    # Then the template's account-specific config
    Dir.glob("#{@config_folder}/*.{yaml,yml,json}").sort.each do |configfile|
      @fullconfig.deep_merge! YAML::load_file(configfile)
    end

    # Then the passed in variables
    @fullconfig.deep_merge! $config.vars

    # Then the output of the pre-hook (if applicable)
    if @hooks_vars and @hooks_vars.is_a?(Hash)
      @fullconfig.deep_merge! @hooks_vars
    end

    # And finally some stack metadata
    @fullconfig.deep_merge! moreopts

    # Now we cache it in a file so that it can be loaded into cfndsl
    File.open(@full_config_file, 'w') { |f| f.write YAML::dump(@fullconfig) }
    @fullconfig
  end


  def with_substacks(acct, region, prettyprint: false, colorize: false, template_bucket: 'none')
    self.fullconfig acct, {
      'account'         => acct,
      'region'          => region,
      'stack_name'      => @name,
      'template_bucket' => template_bucket,
      'template_folder' => @template_folder,
      'config_folder'   => @config_folder,
      'lambdas_folder'  => @lambdas_folder,
      'files_folder'    => @files_folder
    }
    String.disable_colorization = !colorize
    substacks                   = Dir.glob("#{@template_folder}/*.rb")

    # Insert lambdas.rb if needed
    has_lambdas                 = (Dir.exists? @lambdas_folder and (@fullconfig.key? 'lambdas'))
    substacks.push("#{Shellwords.escape(File.dirname(__FILE__))}/builtin/lambdas.rb") if has_lambdas

    # Insert master.rb if needed. This should ALWAYS be at the end of the array!!!!!
    substacks.push("#{Shellwords.escape(File.dirname(__FILE__))}/builtin/master.rb") if substacks.length > 1

    @maintarget = (substacks.length > 0) ? File.basename(substacks.last, '.rb') : nil

    validstacks = []
    substacks.each do |path|
      should_yield = false
      result       = Open3.popen3(
        [
          "cfndsl",
          "-y #{@full_config_file}",
          "#{path}"
        ].join(' ')) { |stdin, stdout, stderr, wait_thr|
        if prettyprint
          begin
            {:stdout => JSON.pretty_generate(JSON.parse(stdout.read)).colorize(:green), :stderr => stderr.read.colorize(:red)}
          rescue JSON::ParserError
            puts '======================================================================================='
            puts "ERROR: Invalid JSON in file #{path}"
            puts '======================================================================================='
            {:stdout => stdout.read.colorize(:red), :stderr => stderr.read.colorize(:red)}
          end
        else
          {:stdout => stdout.read.colorize(:green), :stderr => stderr.read.colorize(:red)}
        end
      }
      # Skip if no resources defined
      # This is necessary so that cloudformation doesn't return an error
      begin
        output = JSON.parse(result[:stdout])
        if output.key? 'Resources'
          validstacks.push(path)
          File.open("#{$tmpdir}/validstacks.yaml", 'w') { |f| f.write YAML::dump(validstacks) }
          should_yield = true
        else
          String.disable_colorization = false
          puts "Substack #{File.basename(path, '.rb')} has no resources..." + 'Skipped'.colorize(:light_blue)
          String.disable_colorization = !colorize
        end
      rescue
        should_yield = true
      end
      yield File.basename(path, '.rb'), result if should_yield
    end
    String.disable_colorization = false
  end


  def run_hook(hookname, account, region, **params)
    self.fullconfig(account)
    hooks_file    = "#{@hooks_folder}/#{hookname}.rb"
    config_folder = @config_folder
    if File.exists? hooks_file
      def IMakeHook
        @hooks_vars = yield
      end

      b = binding
      params.each { |k, v| b.local_variable_set(k.to_sym, v) }
      @fullconfig.each { |k, v| b.local_variable_set(k.to_sym, v) }
      b.eval(File.read(hooks_file))
    end
  end
end
