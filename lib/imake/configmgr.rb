require 'yaml'
require 'deep_merge'

#
# This class handles the config file
# It is able to persist running config across different processes through a file, namely for CfnDsl to query
class ImakeConfig
  # This lets us dynamically create methods in the class
  def metaclass
    class << self;
      self;
    end
  end


  # If the config file does not exist, create one with defaults and notify the user to change settings.
  def initialize(filename)
    @tmpfile = "#{$tmpdir}/running_config.yaml"
    if File.exists?(@tmpfile)
      self.load_running_config
    else
      @filename = filename
      unless File.exists? @filename
        FileUtils.copy "#{File.dirname(__FILE__)}/defaultconfig.yaml", @filename
        puts "Config file #{@filename} did not exist. Defaults written, please edit file and rerun imake."
        exit 0
      end
      @config = YAML::load_file(@filename)
    end
    self.magic_methods
  end


  def set(key, value)
    if DEFAULTCONFIG.key? key.to_sym
      puts 'Success!'
      @config[key.to_sym] = value
      File.open(@filename, 'w') { |f| f.write YAML::dump(@config) }
    end
  end


  def update_running_config(hash)
    @config.deep_merge! hash
    File.open(@tmpfile, 'w') { |f| f.write YAML::dump(@config) }
    self.magic_methods
  end


  def load_running_config
    @config = YAML::load_file(@tmpfile)
  end


  def clear_running_config
    File.delete(@tmpfile) if File.exists?(@tmpfile)
  end

  def magic_methods
    # Magic that makes the hash keys appear as instance methods
    @config.each do |k, v|
      self.metaclass.send(:define_method, k) do
        return @config[k]
      end
    end
  end
end #class ImakeConfig
