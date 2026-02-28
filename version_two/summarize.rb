#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'net/http'
require 'uri'

CLAUDE_API_URL       = 'https://api.anthropic.com/v1/messages'
CLAUDE_MODEL         = 'claude-sonnet-4-6'
ANTHROPIC_API_KEY    = ENV.fetch('ANTHROPIC_API_KEY')
ANTHROPIC_API_VERSION = '2023-06-01'

RAW_DIR       = File.join(__dir__, 'data', 'raw')
SUMMARIES_DIR = File.join(__dir__, 'data', 'summaries')
PROMPT_FILE   = File.join(__dir__, 'prompts', 'summarize.txt')

SLEEP_BETWEEN_CALLS = 2

def main
  FileUtils.mkdir_p(SUMMARIES_DIR)

  prompt = File.read(PROMPT_FILE)
  files  = get_files_to_process(RAW_DIR)

  if files.empty?
    puts "No raw email files found in #{RAW_DIR}"
    exit 0
  end

  processed = 0
  files.each do |file_path|
    processed += 1 if process_file(file_path, prompt)
    sleep SLEEP_BETWEEN_CALLS
  end

  puts "Summarization complete. #{processed}/#{files.size} files processed."
end

def get_files_to_process(directory)
  unless Dir.exist?(directory)
    puts "Directory not found: #{directory}"
    exit 1
  end
  Dir.glob(File.join(directory, '*.md'))
end

def process_file(file_path, prompt)
  puts "Summarizing: #{File.basename(file_path)}"

  begin
    file_content = File.read(file_path)
  rescue => e
    puts "Error reading #{file_path}: #{e.message}"
    return false
  end

  summary = submit_to_claude("<EMAIL>\n#{file_content}\n</EMAIL>", prompt)
  unless summary
    puts "Failed to get summary for #{file_path}"
    return false
  end

  header       = parse_header(file_content)
  claude_score = parse_score(summary)
  output_path  = File.join(SUMMARIES_DIR, summary_filename(File.basename(file_path, '.md')))

  begin
    File.write(output_path, build_summary_file(header, claude_score, summary))
    puts "Saved summary: #{File.basename(output_path)}"
    true
  rescue => e
    puts "Error writing #{output_path}: #{e.message}"
    false
  end
end

def parse_header(content)
  match = content.match(/\A---\n(.*?)\n---/m)
  return {} unless match

  match[1].lines.each_with_object({}) do |line, h|
    k, v = line.split(': ', 2)
    h[k.strip] = v&.strip
  end
end

def parse_score(summary_text)
  match = summary_text.match(/importance score[:\s]+(\d+)/i)
  match ? match[1].to_i : 5
end

def submit_to_claude(content, prompt)
  uri  = URI.parse(CLAUDE_API_URL)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = Net::HTTP::Post.new(uri.request_uri)
  request['x-api-key']         = ANTHROPIC_API_KEY
  request['anthropic-version'] = ANTHROPIC_API_VERSION
  request['content-type']      = 'application/json'

  request.body = {
    model:      CLAUDE_MODEL,
    max_tokens: 1024,
    messages:   [{ role: 'user', content: "#{prompt}\n\n#{content}" }]
  }.to_json

  begin
    response = http.request(request)
    unless response.is_a?(Net::HTTPSuccess)
      puts "Claude API error: #{response.code} - #{response.body}"
      return nil
    end
    JSON.parse(response.body)['content'][0]['text']
  rescue => e
    puts "Error calling Claude API: #{e.message}"
    nil
  end
end

def summary_filename(base)
  "#{base}_summary.md"
end

def build_summary_file(header, claude_score, summary_text)
  <<~MARKDOWN
    ---
    sender: #{header['sender'] || 'TBD'}
    subject: #{header['subject'] || 'TBD'}
    date: #{header['date'] || 'TBD'}
    claude_score: #{claude_score}
    ---

    #{summary_text}
  MARKDOWN
end

main if __FILE__ == $PROGRAM_NAME
