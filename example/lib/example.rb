# frozen_string_literal: true

require_relative 'example/version'

# Load the native extension
# Use RbConfig::CONFIG['ruby_version'] which is the API version (e.g., "3.3.0")
# This matches the path where the extension is installed
begin
  require_relative "example/#{RbConfig::CONFIG['ruby_version']}/example"
rescue LoadError
  require_relative 'example/example'
end
