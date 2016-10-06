#
# This file is loaded by default when a stack uses "require 'imake'"
# It's job is to load all of the helpers in lib/helpers
#
require 'imake/version'
require 'imake/configmgr'
require 'tmpdir'

$tmpdir = "#{Dir::tmpdir}/imake"
FileUtils.mkdir_p $tmpdir unless Dir.exists? $tmpdir

# It also loads config. The config class caches running config, so when cfndsl is called through imake it
# has access to parameters passed in via the CLI
$config = ImakeConfig.new "#{File.expand_path('~')}/.imake"

Dir[File.dirname(__FILE__) + '/imake/helpers/*.rb'].each { |file|
  require file
}
