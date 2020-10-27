# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "whenever_systemd/version"

Gem::Specification.new do |s|
  s.name        = "whenever_systemd"
  s.version     = WheneverSystemd::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Javan Makhmali", "Anton Semenov"]
  s.email       = ["javan@javan.us", "anton.estum@gmail.com"]
  s.license     = "MIT"
  s.homepage    = "https://github.com/estum/whenever"
  s.summary     = %q{Systemd Timers in ruby.}
  s.description = %q{Clean ruby syntax for writing and deploying systemd timers.}
  s.files         = `git ls-files`.split("\n")
  # s.test_files    = `git ls-files -- test/{functional,unit}/*`.split("\n")
  s.executables   = ["whenever_systemd", "wheneverize"]
  s.require_paths = ["lib"]
  s.required_ruby_version = ">= 2.6"

  s.add_dependency "activesupport", ">= 5.2"
  s.add_development_dependency "bundler"
end