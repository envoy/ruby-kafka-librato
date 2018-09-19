# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'kafka/librato/version'

Gem::Specification.new do |spec|
  spec.name          = "ruby-kafka-librato"
  spec.version       = Kafka::Librato::VERSION
  spec.authors       = ["Kamal Mahyuddin"]
  spec.email         = ["kamal@envoy.com"]

  spec.summary       = %q{Report ruby-kafka metrics to Librato}
  spec.homepage      = "http://github.com/envoy/ruby-kafka-librato"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "ruby-kafka", "~> 0.7.1"
  spec.add_dependency "librato-rails", "~> 2.1.0"
  spec.add_dependency "activesupport"

  spec.add_development_dependency "bundler", "~> 1.14"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
