require 'yaml'
require 'erb'
require 'uglifier'

class Fileman
  def initialize (filename=nil)
    @filename = filename
  end


  def in_folder(folder)
    @filename = folder.dup
    self
  end


  def open(filename)
    @filename << '/' + filename
    self
  end


  def with_runtime(runtime)
    filetypes = {
      'js'   => /nodejs/,
      'py'   => /python/,
      'java' => /java/
    }
    filetypes.each do |type, rt|
      if rt.match runtime
        @filename << '.' + type
      end
    end
    self
  end


  def serialize
    if @filename.end_with? '.js'
      Uglifier.compile(File.read(@filename))
    else
      File.readlines(@filename).collect { |line| line.strip + ' ' }.join
    end
  end

  def to_userdata
    {'Fn::Base64' => {'Fn::Join' => ["", File.readlines(@filename)]}}
  end

  def arrayified_join
    {'Fn::Join' => ["\n", File.readlines(@filename).collect { |line| line.strip }]}
  end


  def as_template(with_binding)
    ERB.new(File.read(@filename)).result(with_binding)
  end
end

class String
  def to_cmdlist
    cmdlist = {}
    cmdno   = 1
    self.each_line do |line|
      cmdlist['command_' + cmdno.to_s.rjust(4, '0')] = {'Fn::Join' => ['', [line]]}
      cmdno                                          += 1
    end
    cmdlist
  end
  def to_cfnarray
    {'Fn::Join' => ["\n", self.each_line.collect { |line| line.strip }]}
  end
end
