# frozen_string_literal: true

require 'base64'
require 'cgi'
require 'json'
require 'net/http'
require 'time'
require 'uri'

module ContentAggregator
  class GmailClient
    GMAIL_API_BASE_URL = 'https://gmail.googleapis.com/gmail/v1'.freeze
    GMAIL_OAUTH_TOKEN_URL = 'https://oauth2.googleapis.com/token'.freeze

    def initialize(gmail_config, logger: $stdout, now: Time.now.utc)
      @gmail_config = gmail_config
      @logger = logger
      @now = now
    end

    def fetch_messages
      query = build_query(
        senders: @gmail_config['query_senders'],
        lookback_hours: @gmail_config['lookback_hours']
      )

      message_refs = list_message_references(query: query, max_results: @gmail_config['max_results'])
      message_refs.map { |message_ref| fetch_message_detail(message_ref, query) }.compact
    end

    def build_query(senders:, lookback_hours:)
      sender_clause = build_sender_clause(senders)
      after_unix_seconds = (@now - (lookback_hours.to_i * 3600)).to_i

      query_terms = []
      query_terms << sender_clause unless sender_clause.empty?
      query_terms << "after:#{after_unix_seconds}"

      query_terms.join(' ')
    end

    private

    def build_sender_clause(senders)
      safe_senders = Array(senders).map(&:to_s).map(&:strip).reject(&:empty?)
      return '' if safe_senders.empty?

      return "from:#{safe_senders.first}" if safe_senders.length == 1

      sender_parts = safe_senders.map { |sender| "from:#{sender}" }
      "(#{sender_parts.join(' OR ')})"
    end

    def list_message_references(query:, max_results:)
      encoded_query = CGI.escape(query)
      user_id = @gmail_config['user_id'] || 'me'
      desired_count = max_results.to_i
      desired_count = 100 if desired_count <= 0

      fetched_refs = []
      next_page_token = nil

      while fetched_refs.length < desired_count
        batch_size = [desired_count - fetched_refs.length, 100].min
        endpoint = "#{GMAIL_API_BASE_URL}/users/#{CGI.escape(user_id)}/messages"
        endpoint += "?q=#{encoded_query}&maxResults=#{batch_size}"
        endpoint += "&pageToken=#{CGI.escape(next_page_token)}" if next_page_token

        response_json = get_json(endpoint)
        fetched_refs.concat(Array(response_json['messages']))
        next_page_token = response_json['nextPageToken']

        break if next_page_token.nil? || next_page_token.empty?
      end

      fetched_refs.first(desired_count)
    end

    def fetch_message_detail(message_ref, source_query)
      message_id = message_ref['id']
      thread_id = message_ref['threadId']
      return nil if message_id.nil? || message_id.empty?

      user_id = @gmail_config['user_id'] || 'me'
      endpoint = "#{GMAIL_API_BASE_URL}/users/#{CGI.escape(user_id)}/messages/#{CGI.escape(message_id)}?format=full"
      response_json = get_json(endpoint)

      payload = response_json['payload'] || {}
      headers = index_headers(payload['headers'])
      body_text = extract_body_text(payload)

      {
        'gmail_message_id' => message_id,
        'thread_id' => thread_id,
        'sender' => headers['from'] || 'UNKNOWN_SENDER',
        'subject' => headers['subject'] || 'No subject',
        'received_at' => parse_header_time(headers['date']),
        'snippet' => response_json['snippet'].to_s,
        'body_text' => body_text,
        'labels' => Array(response_json['labelIds']),
        'retrieved_at' => Time.now.utc.iso8601,
        'source_query' => source_query
      }
    rescue StandardError => error
      @logger.puts("Failed to fetch message detail for #{message_id}: #{error.message}")
      nil
    end

    def index_headers(headers_array)
      indexed_headers = {}
      Array(headers_array).each do |header|
        next unless header.is_a?(Hash)

        name = header['name'].to_s.downcase
        value = header['value'].to_s
        next if name.empty?

        indexed_headers[name] = value
      end
      indexed_headers
    end

    def parse_header_time(header_value)
      return Time.now.utc.iso8601 if header_value.nil? || header_value.empty?

      Time.parse(header_value).utc.iso8601
    rescue StandardError
      Time.now.utc.iso8601
    end

    def extract_body_text(payload)
      if payload['parts'].is_a?(Array)
        plain_text_part = find_part(payload['parts'], 'text/plain')
        html_part = find_part(payload['parts'], 'text/html')

        return decode_base64_urlsafe(plain_text_part.dig('body', 'data')) if plain_text_part
        return strip_html(decode_base64_urlsafe(html_part.dig('body', 'data'))) if html_part
      end

      return decode_base64_urlsafe(payload.dig('body', 'data')) if payload.dig('body', 'data')

      ''
    end

    def find_part(parts, mime_type)
      Array(parts).each do |part|
        return part if part['mimeType'] == mime_type

        nested_part = find_part(part['parts'], mime_type)
        return nested_part if nested_part
      end
      nil
    end

    def decode_base64_urlsafe(encoded_data)
      return '' if encoded_data.nil? || encoded_data.empty?

      padded_data = encoded_data.tr('-_', '+/')
      padding = (4 - padded_data.length % 4) % 4
      padded_data += '=' * padding

      Base64.decode64(padded_data)
    rescue StandardError
      ''
    end

    def strip_html(html_text)
      html_text.to_s.gsub(%r{<[^>]+>}, ' ').gsub(/\s+/, ' ').strip
    end

    def get_json(url)
      response = perform_get(url)
      raise "Gmail API request failed: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end

    def perform_get(url)
      uri = URI.parse(url)
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{access_token}"
      request['Accept'] = 'application/json'

      send_http_request(uri, request)
    end

    def access_token
      from_environment = ENV['GMAIL_ACCESS_TOKEN']
      return from_environment if from_environment && !from_environment.empty?

      refresh_access_token
    end

    def refresh_access_token
      client_id = ENV['GMAIL_CLIENT_ID']
      client_secret = ENV['GMAIL_CLIENT_SECRET']
      refresh_token = ENV['GMAIL_REFRESH_TOKEN']

      missing_values = []
      missing_values << 'GMAIL_CLIENT_ID' if client_id.to_s.empty?
      missing_values << 'GMAIL_CLIENT_SECRET' if client_secret.to_s.empty?
      missing_values << 'GMAIL_REFRESH_TOKEN' if refresh_token.to_s.empty?

      unless missing_values.empty?
        raise "Missing Gmail auth settings: #{missing_values.join(', ')}. Configure env vars or set GMAIL_ACCESS_TOKEN."
      end

      uri = URI.parse(GMAIL_OAUTH_TOKEN_URL)
      request = Net::HTTP::Post.new(uri)
      request['Content-Type'] = 'application/x-www-form-urlencoded'
      request.body = URI.encode_www_form(
        client_id: client_id,
        client_secret: client_secret,
        refresh_token: refresh_token,
        grant_type: 'refresh_token'
      )

      response = send_http_request(uri, request)
      raise "OAuth token refresh failed: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

      parsed_body = JSON.parse(response.body)
      token = parsed_body['access_token']
      raise 'OAuth token refresh response did not include access_token' if token.nil? || token.empty?

      token
    end

    def send_http_request(uri, request)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 90
      http.open_timeout = 30
      http.request(request)
    end
  end
end
