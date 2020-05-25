# -*- encoding: utf-8 -*-
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('lib', __dir__)

require 'distillery/version'

# NOTE: 'distillery' name is taken but not used since 2012
#       https://rubygems.org/gems/distillery

Gem::Specification.new do |s|
    s.name          = 'rom-distillery'
    s.version       = Distillery::VERSION
    s.platform      = Gem::Platform::RUBY
    s.licenses      = [ 'EUPL-1.2' ]
    s.summary       = 'ROM manager'
    s.description   = 'Help organise emulation ROM using DAT file'

    s.required_ruby_version = '>= 2.5'

    s.authors       = [ 'Stéphane D\'Alu' ]
    s.email         = [ 'sdalu@sdalu.com' ]
    s.homepage      = 'http://github.com/sdalu/distillery'

    s.add_dependency 'nokogiri'
    s.add_dependency 'rubyzip'
    s.add_dependency 'tty-logger'
    s.add_dependency 'tty-progressbar'
    s.add_dependency 'tty-screen'
    s.add_dependency 'tty-spinner'

    s.add_development_dependency 'rake'
    s.add_development_dependency 'yard'

    s.executables   = [ 'rhum' ]
    s.files         = %w[ LICENSE README.md Gemfile distillery.gemspec ] +
                      Dir['lib/**/*.{rb,yaml}']
end
