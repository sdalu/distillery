# -*- encoding: utf-8 -*-
$:.unshift File.expand_path("../lib", __FILE__)
require "distillery/version"

# NOTE: 'distillery' name is taken but not used since 2012
#       https://rubygems.org/gems/distillery

Gem::Specification.new do |s|
  s.name          = "rom-distillery"	
  s.version       = Distillery::VERSION
  s.platform      = Gem::Platform::RUBY
  s.licenses      = [ 'EUPL-1.2' ]
  s.summary       = "ROM manager"
  s.description   = "Help organise emulation ROM using DAT file"

  s.required_ruby_version = '>= 2.5'
  
  s.authors       = ["Stephane D'Alu"]
  s.email         = ["sdalu@sdalu.com"]
  s.homepage      = "http://github.com/sdalu/distillery"

  s.add_dependency 'nokogiri'
  s.add_dependency 'rubyzip'
  s.add_dependency 'tty-screen'
  s.add_dependency 'tty-logger'
  s.add_dependency 'tty-spinner'
  s.add_dependency 'tty-progressbar'
  
  s.add_development_dependency "yard"
  s.add_development_dependency "rake"

  s.executables   = [ 'rhum' ]
  s.files         =  %w[ LICENSE README.md Gemfile distillery.gemspec ] +
		     Dir['lib/**/*.rb'  ] +
                     Dir['lib/**/*.yaml']
  
end

