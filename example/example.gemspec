# frozen_string_literal: true

require_relative "lib/example/version"

Gem::Specification.new do |spec|
  spec.name = "example"
  spec.version = Example::VERSION
  spec.authors = ["Your Name"]
  spec.email = ["your.email@example.com"]

  spec.summary = "Example Ruby extension written in Zig"
  spec.description = "A minimal example demonstrating how to create Ruby extensions using Zig"
  spec.homepage = "https://github.com/yourusername/example"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # Only include Ruby files and the compiled extension
  spec.files = Dir[
    "lib/**/*.{rb,so}",
    "README.md",
    "LICENSE.txt"
  ]
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  
  # No extensions - we ship the pre-compiled .so file

  # Development dependencies
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "minitest", "~> 5.0"
end
