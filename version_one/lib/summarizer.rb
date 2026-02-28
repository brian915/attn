# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

class Summarizer
  def initialize(config, base_dir = nil, verbose = false)
    @config = config
    @verbose = verbose
    @base_dir = base_dir
    @llm = config['llm'] || {}
  end

  def summarize(email)
    puts "Summarizing: #{email[:subject]}" if @verbose

    content = build_prompt(email)
    response = call_llm(content)

    summary = {
      email_id: email[:gmail_id] || email[:filename],
      subject: email[:subject],
      from: email[:from],
      summary: response,
      summarized_at: Time.now.utc.iso8601,
      stored_path: email[:stored_path],
      has_attachments: email[:has_attachments]
    }

    save_summary(summary)
    summary
  end

  private

  def build_prompt(email)
    <<~PROMPT
      Summarize the following email concisely (2-3 sentences).
      Focus on the main point and any actionable items.

      From: #{email[:from]}
      Subject: #{email[:subject]}

      Body:
      #{email[:body] || email[:snippet] || '[No body content]'}
    PROMPT
  end

  def call_llm(content)
    api_url = @llm['api_url'] || 'https://api.openai.com/v1/chat/completions'
    model = @llm['model'] || 'gpt-4.1-2025-04-14'
    api_key = @llm['api_key']

    unless api_key
      puts "No API key configured, returning placeholder summary"
      return "[Summary not generated - no API key configured]"
    end

    uri = URI.parse(api_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.request_uri)
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{api_key}"

    request.body = {
      model: model,
      messages: [
        { role: 'user', content: content }
      ],
      temperature: 0.5,
      max_tokens: 300
    }.to_json

    begin
      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        puts "LLM API error: #{response.code}"
        return "[Summary generation failed]"
      end

      result = JSON.parse(response.body)
      result['choices'][0]['message']['content']
    rescue => e
      puts "LLM error: #{e.message}"
      "[Summary generation error: #{e.message}]"
    end
  end

  def save_summary(summary)
    return unless @base_dir

    summary_dir = File.join(@base_dir, 'summaries')
    FileUtils.mkdir_p(summary_dir)

    filename = "summary_#{summary[:email_id]}.md"
    filepath = File.join(summary_dir, filename)

    content = <<~MARKDOWN
      ---
      email_id: #{summary[:email_id]}
      subject: #{summary[:subject]}
      from: #{summary[:from]}
      summarized_at: #{summary[:summarized_at]}
      ---

      # #{summary[:subject]}

      **From:** #{summary[:from]}

      ## Summary

      #{summary[:summary]}

      ---

      [Original email](./#{summary[:stored_path]})
    MARKDOWN

    File.write(filepath, content)
    puts "Saved summary: #{filepath}" if @verbose
  end
end
