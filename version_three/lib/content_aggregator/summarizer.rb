# frozen_string_literal: true

require 'json'
require 'net/http'
require 'time'
require 'uri'

module ContentAggregator
  class Summarizer
    OPENAI_CHAT_COMPLETIONS_URL = 'https://api.openai.com/v1/chat/completions'.freeze

    def initialize(llm_config, logger: $stdout)
      @llm_config = llm_config
      @logger = logger
    end

    def summarize_message(message)
      parsed_content = summarize_with_llm(message)

      {
        'summary_text' => parsed_content['summary'],
        'why_it_matters' => parsed_content['why_it_matters'],
        'key_signals' => parsed_content['key_signals'],
        'summary_source' => parsed_content['summary_source']
      }
    rescue StandardError => error
      @logger.puts("LLM summary failed for #{message['gmail_message_id']}: #{error.message}")
      fallback_summary(message, 'LLM request failed')
    end

    def rank_story_ids(summary_records, top_n)
      return [] if summary_records.empty?

      response_json = request_story_ranking(summary_records, top_n)
      selected_ids = Array(response_json['selected_ids']).map(&:to_s)

      selected_ids.select { |story_id| summary_records.any? { |record| record['gmail_message_id'] == story_id } }
    rescue StandardError => error
      @logger.puts("LLM ranking failed: #{error.message}")
      []
    end

    private

    def summarize_with_llm(message)
      api_key = ENV['LLM_API_KEY']
      raise 'LLM_API_KEY is not set (TBD)' if api_key.to_s.empty?
      raise "Unsupported LLM provider: #{@llm_config['provider']}" unless @llm_config['provider'].to_s.downcase == 'openai'

      prompt = build_summary_prompt(message)
      response_json = call_openai_chat_completions(api_key: api_key, prompt: prompt)

      raw_content = response_json.dig('choices', 0, 'message', 'content').to_s
      parsed_json = parse_json_response(raw_content)

      {
        'summary' => safe_field(parsed_json['summary'], fallback: fallback_summary_sentence(message)),
        'why_it_matters' => safe_field(parsed_json['why_it_matters'], fallback: 'TBD'),
        'key_signals' => sanitize_array(parsed_json['key_signals']),
        'summary_source' => 'llm'
      }
    end

    def request_story_ranking(summary_records, top_n)
      api_key = ENV['LLM_API_KEY']
      raise 'LLM_API_KEY is not set (TBD)' if api_key.to_s.empty?

      prompt = build_ranking_prompt(summary_records, top_n)
      response = call_openai_chat_completions(api_key: api_key, prompt: prompt)
      parse_json_response(response.dig('choices', 0, 'message', 'content').to_s)
    end

    def build_summary_prompt(message)
      <<~PROMPT
        You are summarizing one email message for a daily content digest.
        Respond with valid JSON only using keys: summary, why_it_matters, key_signals.

        Constraints:
        - summary: 2-4 sentences.
        - why_it_matters: 1-2 sentences.
        - key_signals: array of 3 short bullet-like strings.

        Message Metadata:
        - gmail_message_id: #{message['gmail_message_id']}
        - sender: #{message['sender']}
        - subject: #{message['subject']}
        - received_at: #{message['received_at']}

        Message Body:
        #{message['body_text']}
      PROMPT
    end

    def build_ranking_prompt(summary_records, top_n)
      ranked_candidates = summary_records.map do |record|
        {
          gmail_message_id: record['gmail_message_id'],
          sender: record['sender'],
          subject: record['subject'],
          summary_text: record['summary_text'],
          why_it_matters: record['why_it_matters'],
          heuristic_score: record['heuristic_score']
        }
      end

      <<~PROMPT
        You are selecting top stories for a daily digest.
        Use heuristic_score as an input signal but choose the most meaningful stories.

        Return valid JSON only with keys:
        - selected_ids: array of message IDs in descending priority (max #{top_n})

        Candidate Stories:
        #{JSON.pretty_generate(ranked_candidates)}
      PROMPT
    end

    def call_openai_chat_completions(api_key:, prompt:)
      uri = URI.parse(OPENAI_CHAT_COMPLETIONS_URL)
      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{api_key}"
      request['Content-Type'] = 'application/json'
      request['Accept'] = 'application/json'

      request.body = {
        model: @llm_config['model'],
        temperature: @llm_config['temperature'],
        max_tokens: @llm_config['max_tokens'],
        messages: [
          { role: 'user', content: prompt }
        ]
      }.to_json

      response = send_http_request(uri, request)
      unless response.is_a?(Net::HTTPSuccess)
        raise "LLM request failed: #{response.code} #{response.message} #{response.body}"
      end

      JSON.parse(response.body)
    end

    def send_http_request(uri, request)
      timeout = @llm_config['timeout_seconds'].to_i
      timeout = 60 if timeout <= 0

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = [timeout / 2, 5].max
      http.read_timeout = timeout
      http.request(request)
    end

    def parse_json_response(text)
      cleaned_text = text.strip

      if cleaned_text.start_with?('```')
        cleaned_text = cleaned_text.gsub(/\A```[a-zA-Z]*\n?/, '')
        cleaned_text = cleaned_text.gsub(/\n?```\z/, '')
      end

      JSON.parse(cleaned_text)
    rescue JSON::ParserError
      {
        'summary' => cleaned_text.empty? ? 'TBD' : cleaned_text,
        'why_it_matters' => 'TBD',
        'key_signals' => ['TBD']
      }
    end

    def fallback_summary(message, reason)
      {
        'summary_text' => fallback_summary_sentence(message),
        'why_it_matters' => "TBD (#{reason})",
        'key_signals' => ['TBD'],
        'summary_source' => 'fallback'
      }
    end

    def fallback_summary_sentence(message)
      first_line = message['body_text'].to_s.split("\n").map(&:strip).find { |line| !line.empty? }
      return first_line if first_line && !first_line.empty?

      message['snippet'].to_s.empty? ? 'TBD summary content' : message['snippet']
    end

    def sanitize_array(values)
      safe_values = Array(values).map(&:to_s).map(&:strip).reject(&:empty?)
      safe_values.empty? ? ['TBD'] : safe_values
    end

    def safe_field(value, fallback:)
      text = value.to_s.strip
      text.empty? ? fallback : text
    end
  end
end
