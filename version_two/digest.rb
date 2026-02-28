#!/usr/bin/env ruby
# frozen_string_literal: true

SCRIPT_DIR = __dir__

PHASE_SCRIPTS = [
  File.join(SCRIPT_DIR, 'fetch_gmail.rb'),
  File.join(SCRIPT_DIR, 'summarize.rb'),
  File.join(SCRIPT_DIR, 'build_digest.rb')
].freeze

def main
  puts "Starting content digest -- #{Time.now}"

  PHASE_SCRIPTS.each do |script|
    phase_name = File.basename(script, '.rb')
    puts "\n=== Phase: #{phase_name} ==="

    success = system(RbConfig.ruby, script)
    unless success
      puts "Phase #{phase_name} failed. Aborting."
      exit 1
    end
  end

  puts "\nDigest complete -- #{Time.now}"
end

main if __FILE__ == $PROGRAM_NAME
