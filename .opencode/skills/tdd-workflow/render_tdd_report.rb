#!/usr/bin/env ruby
# frozen_string_literal: true

# Deterministic renderer for the TDD report.
# Injects a JSON payload into the fixed HTML template.
#
# Usage:
#   ruby render_tdd_report.rb <data.json> [output.html]
#
# Defaults output to .tmp/tdd-report.html relative to the current directory.

require "json"
require "fileutils"

data_path = ARGV[0]
output_path = ARGV[1] || ".tmp/tdd-report.html"

abort "Usage: ruby render_tdd_report.rb <data.json> [output.html]" if data_path.nil? || data_path.empty?
abort "Data file not found: #{data_path}" unless File.exist?(data_path)

template_path = File.join(__dir__, "tdd-report-template.html")
abort "Template not found: #{template_path}" unless File.exist?(template_path)

raw = File.read(data_path)
data = JSON.parse(raw)

# Validate JSON round-trips to avoid injecting broken JS.
payload = JSON.generate(data)

template = File.read(template_path)
abort "Template missing DATA_PLACEHOLDER token" unless template.include?("DATA_PLACEHOLDER")

html = template.sub("DATA_PLACEHOLDER", payload)

FileUtils.mkdir_p(File.dirname(output_path))
File.write(output_path, html)

puts "Wrote #{output_path}"
