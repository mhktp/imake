# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'imake/version'

Gem::Specification.new do |spec|
  spec.name          = 'imake'
  spec.version       = Imake::VERSION
  spec.authors       = ['Andrew Khoury', 'Shayne Clausson', 'Brian Jakovich']
  spec.email         = ['akhoury@live.com', 'shayne.clausson@stelligent.com', 'brian.jakovich@stelligent.com']

  spec.summary       = %q{Ruby framework for managing AWS cloudformation and API calls.}
  spec.description   = %q{Ruby framework for managing AWS cloudformation and API calls.}
  spec.homepage      = 'http://github.com/KaplanTestPrep/imake'
  spec.licenses      = 'Nonstandard'

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  # if spec.respond_to?(:metadata)
  #   spec.metadata['allowed_push_host'] = ''
  # else
  #   raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  # end

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(\.rbenv(.+)|test|spec|features)}) }
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.required_ruby_version = '~> 2.3.0'

  spec.add_runtime_dependency 'cfndsl', '0.4.3'
  spec.add_runtime_dependency 'trollop', '~> 2.1'
  spec.add_runtime_dependency 'aws-sdk', '~> 2'
  spec.add_runtime_dependency 'netaddr', '~> 1.5'
  spec.add_runtime_dependency 'colorize', '~> 0.8'
  spec.add_runtime_dependency 'deep_merge', '~> 1'
  spec.add_runtime_dependency 'uglifier', '~> 3.0'

  spec.add_development_dependency 'bundler', '~> 1.12'
  spec.add_development_dependency 'rake', '~> 10.0'
end
