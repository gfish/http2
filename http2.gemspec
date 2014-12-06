# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-
# stub: http2 0.0.29 ruby lib

Gem::Specification.new do |s|
  s.name = "http2"
  s.version = "0.0.29"

  s.require_paths = ["lib"]
  s.authors = ["Kasper Johansen"]
  s.description = "A lightweight framework for doing http-connections in Ruby. Supports cookies, keep-alive, compressing and much more."
  s.email = "k@spernj.org"
  s.extra_rdoc_files = [
    "LICENSE.txt",
    "README.md"
  ]
  s.files = Dir["{include,lib}/**/*"] + ["Rakefile"]
  s.test_files = Dir["spec/**/*"]
  s.homepage = "http://github.com/kaspernj/http2"
  s.licenses = ["MIT"]
  s.rubygems_version = "2.4.0"
  s.summary = "A lightweight framework for doing http-connections in Ruby. Supports cookies, keep-alive, compressing and much more."

  s.add_runtime_dependency("string-cases", ">= 0")
  s.add_development_dependency("rake")
  s.add_development_dependency("rspec", "~> 2.8.0")
  s.add_development_dependency("rdoc", "~> 3.12")
  s.add_development_dependency("bundler", ">= 1.0.0")
  s.add_development_dependency("hayabusa", ">= 0.0.25")
  s.add_development_dependency("sqlite3")
  s.add_development_dependency("codeclimate-test-reporter")
end

