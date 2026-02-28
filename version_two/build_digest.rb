#!/usr/bin/env ruby
# frozen_string_literal: true

require 'date'
require 'fileutils'
require 'json'
require 'net/http'
require 'uri'

CLAUDE_API_URL        = 'https://api.anthropic.com/v1/messages'
CLAUDE_MODEL          = 'claude-sonnet-4-6'
ANTHROPIC_API_KEY     = ENV.fetch('ANTHROPIC_API_KEY')
ANTHROPIC_API_VERSION = '2023-06-01'

SUMMARIES_DIR    = File.join(__dir__, 'data', 'summaries')
DIGESTS_DIR      = File.join(__dir__, 'data', 'digests')
RANK_PROMPT_FILE = File.join(__dir__, 'prompts', 'rank.txt')

TOP_N = 5

# Sender priority: 3 = highest, 1 = lowest.
# Add known sender email addresses (without angle brackets) here.
SENDER_PRIORITY = {
  'TBD@example.com'  => 3,
  'TBD2@example.com' => 2
}.freeze

def main
  FileUtils.mkdir_p(DIGESTS_DIR)

  rank_prompt = File.read(RANK_PROMPT_FILE)
  files       = get_summary_files

  if files.empty?
    puts "No summary files found in #{SUMMARIES_DIR}"
    exit 0
  end

  puts "Ranking #{files.size} summaries..."
  ranked      = rank_summaries(files)
  top_stories = ranked.first(TOP_N)

  puts "Building digest from top #{top_stories.size} stories..."
  editorial = generate_editorial(top_stories, rank_prompt)

  digest = build_digest(top_stories, editorial)
  puts "\n" + digest
  save_digest(digest)
end

def get_summary_files
  unless Dir.exist?(SUMMARIES_DIR)
    puts "Summaries directory not found: #{SUMMARIES_DIR}"
    exit 1
  end
  Dir.glob(File.join(SUMMARIES_DIR, '*_summary.md'))
end

def rank_summaries(files)
  files.map do |file_path|
    content       = File.read(file_path)
    header        = parse_header(content)
    claude_score  = (header['claude_score'] || '5').to_i
    s_priority    = sender_priority_for(header['sender'])
    recency       = recency_score(header['date'])
    weighted      = (claude_score * 0.7) + (s_priority * 0.2) + (recency * 0.1)

    {
      file_path:     file_path,
      header:        header,
      content:       content,
      claude_score:  claude_score,
      weighted_score: weighted.round(2)
    }
  end.sort_by { |s| -s[:weighted_score] }
end

def parse_header(content)
  match = content.match(/\A---\n(.*?)\n---/m)
  return {} unless match

  match[1].lines.each_with_object({}) do |line, h|
    k, v = line.split(': ', 2)
    h[k.strip] = v&.strip
  end
end

def sender_priority_for(sender)
  return 1 unless sender
  email = sender.match(/<(.+?)>/)&.[](1) || sender
  SENDER_PRIORITY[email] || 1
end

def recency_score(date_str)
  return 1.0 unless date_str
  days_old = (Date.today - Date.parse(date_str)).to_i
  [1.0 - (days_old * 0.1), 0.5].max
rescue
  0.7
end

def generate_editorial(top_stories, prompt)
  summary_text = top_stories.each_with_index.map do |story, i|
    "#{i + 1}. #{story[:header]['subject']} (#{story[:header]['sender']})\n#{story[:content]}"
  end.join("\n\n---\n\n")

  submit_to_claude(summary_text, prompt) || '[Editorial generation failed]'
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

def build_digest(top_stories, editorial)
  today = Date.today.strftime('%Y-%m-%d')
  lines = ["# Daily Digest -- #{today}", '', '## Top Stories', '']

  top_stories.each_with_index do |story, i|
    header       = story[:header]
    summary_link = File.basename(story[:file_path])
    lines << "#{i + 1}. **#{header['subject']}** (#{header['sender']})"
    lines << "   Score: #{story[:weighted_score]} | [Full summary](../summaries/#{summary_link})"
    lines << ''
  end

  lines << "## Editor's Note"
  lines << ''
  lines << editorial
  lines << ''

  lines.join("\n")
end

def save_digest(digest)
  today       = Date.today.strftime('%Y%m%d')
  output_path = File.join(DIGESTS_DIR, "#{today}_digest.md")
  File.write(output_path, digest)
  puts "Digest saved to: #{output_path}"
end

main if __FILE__ == $PROGRAM_NAME
