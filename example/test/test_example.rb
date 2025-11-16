#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for the example extension
# This demonstrates how to use the extension and verifies it works correctly

require_relative '../lib/example'

puts "Testing Example.add function..."

# Test basic addition
result = Example.add(2, 3)
puts "Example.add(2, 3) = #{result}"
raise "Expected 5, got #{result}" unless result == 5

# Test with negative numbers
result = Example.add(-5, 10)
puts "Example.add(-5, 10) = #{result}"
raise "Expected 5, got #{result}" unless result == 5

# Test with zero
result = Example.add(0, 0)
puts "Example.add(0, 0) = #{result}"
raise "Expected 0, got #{result}" unless result == 0

# Test with large numbers
result = Example.add(1_000_000, 2_000_000)
puts "Example.add(1_000_000, 2_000_000) = #{result}"
raise "Expected 3000000, got #{result}" unless result == 3_000_000

puts "\n✓ All tests passed!"
