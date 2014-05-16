# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'npm/mirror/version'

Gem::Specification.new do |spec|
  spec.name          = "npm-mirror"
  spec.version       = Npm::Mirror::VERSION
  spec.authors       = ["Yue Du"]
  spec.email         = ["ifduyue@gmail.com"]
  spec.summary       = %q{NPM Mirror}
  spec.homepage      = "https://github.com/ifduyue/npm-mirror"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "net-http-persistent", "~> 2.9.4"
  spec.add_dependency "json"

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "pry"
end
