# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

class EmailFetcher
  def initialize(config, verbose = false)
    @config = config
    @verbose = verbose
    @adapter = select_adapter
  end

  def fetch
    @adapter.fetch
  end

  private

  def select_adapter
    source_type = @config['email']['source'] || 'gmail'

    case source_type
    when 'gmail'
      GmailAdapter.new(@config, @verbose)
    when 'imap'
      ImapAdapter.new(@config, @verbose)
    when 'mbox'
      MboxAdapter.new(@config, @verbose)
    else
      raise "Unknown email source: #{source_type}"
    end
  end
end

class GmailAdapter
  def initialize(config, verbose = false)
    @config = config
    @verbose = verbose
    @credentials = config['email']['gmail']
  end

  def fetch
    puts "Connecting to Gmail API..." if @verbose
    message_ids = list_messages
    
    puts "Found #{message_ids.size} messages, fetching details..." if @verbose
    
    messages = message_ids.map do |msg_id|
      fetch_message_details(msg_id)
    end.compact
    
    apply_blocked_senders_filter(messages)
  end

  def list_messages
    access_token = get_access_token
    query = build_query

    uri = URI.parse("https://gmail.googleapis.com/gmail/v1/users/me/messages?#{query}&maxResults=50")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri.request_uri)
    request['Authorization'] = "Bearer #{access_token}"

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      puts "Gmail API error: #{response.code} - #{response.message}"
      return []
    end

    result = JSON.parse(response.body)
    result['messages'] || []
  end

  def fetch_message_details(msg_id)
    access_token = get_access_token
    
    uri = URI.parse("https://gmail.googleapis.com/gmail/v1/users/me/messages/#{msg_id}?format=full")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri.request_uri)
    request['Authorization'] = "Bearer #{access_token}"

    response = http.request(request)

    return nil unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    parse_gmail_message(data)
  end

  def parse_gmail_message(msg)
    headers = msg['payload']['headers'] || []
    header_hash = headers.each_with_object({}) { |h, hash| hash[h['name'].downcase] = h['value'] }

    body = extract_body(msg['payload'])
    
    {
      gmail_id: msg['id'],
      thread_id: msg['threadId'],
      from: header_hash['from'],
      to: header_hash['to'],
      subject: header_hash['subject'],
      date: header_hash['date'],
      snippet: msg['snippet'],
      body: body,
      has_attachments: msg['payload']['filename'] && !msg['payload']['filename'].empty?,
      retrieved_at: Time.now.utc.iso8601
    }
  end

  def extract_body(payload)
    return nil unless payload

    if payload['body'] && payload['body']['data']
      decode_base64_url(payload['body']['data'])
    elsif payload['parts']
      payload['parts'].each do |part|
        if part['mimeType'] == 'text/plain' && part['body'] && part['body']['data']
          return decode_base64_url(part['body']['data'])
        end
      end
    end
    nil
  end

  def decode_base64_url(str)
    str.tr('-_', '+/').gsub(/\s/, '').unpack1('m0')
  end

  def get_access_token
    refresh_token = @credentials['refresh_token']
    client_id = @credentials['client_id']
    client_secret = @credentials['client_secret']

    uri = URI.parse('https://oauth2.googleapis.com/token')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.request_uri)
    request['Content-Type'] = 'application/x-www-form-urlencoded'

    request.body = {
      client_id: client_id,
      client_secret: client_secret,
      refresh_token: refresh_token,
      grant_type: 'refresh_token'
    }.map { |k, v| "#{k}=#{URI.encode_www_form_component(v)}" }.join('&')

    response = http.request(request)
    data = JSON.parse(response.body)
    data['access_token']
  end

  def build_query
    filters = @config['email']['filters'] || {}
    queries = []

    if filters['from']
      queries << "from:#{filters['from']}"
    end

    if filters['subject']
      queries << "subject:#{filters['subject']}"
    end

    if filters['after']
      queries << "after:#{filters['after']}"
    end

    if filters['before']
      queries << "before:#{filters['before']}"
    end

    queries << "is:unread" if filters['unread_only']
    queries << "has:attachment" if filters['has_attachments']

    "q=#{URI.encode_www_form_component(queries.join(' '))}"
  end

  def apply_blocked_senders_filter(messages)
    blocked = @config['email']['filters']['blocked_senders'] || []
    return messages if blocked.empty?

    messages.reject do |msg|
      from = msg[:from] || ''
      blocked.any? { |blocked_sender| from.include?(blocked_sender) }
    end
  end
end

class ImapAdapter
  def initialize(config, verbose = false)
    @config = config
    @verbose = verbose
    @credentials = config['email']['imap']
  end

  def fetch
    puts "IMAP adapter not yet implemented" if @verbose
    []
  end
end

class MboxAdapter
  def initialize(config, verbose = false)
    @config = config
    @verbose = verbose
    @path = config['email']['mbox_path']
  end

  def fetch
    puts "MBOX adapter not yet implemented" if @verbose
    []
  end
end
