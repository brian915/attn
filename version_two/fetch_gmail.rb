#!/usr/bin/env ruby
# frozen_string_literal: true

require 'base64'
require 'date'
require 'fileutils'
require 'google/apis/gmail_v1'
require 'googleauth'
require 'googleauth/stores/file_token_store'

CREDENTIALS_PATH = File.join(__dir__, 'credentials.json')
TOKEN_PATH       = File.join(__dir__, 'token.yaml')
SCOPE            = Google::Apis::GmailV1::AUTH_GMAIL_READONLY
OOB_URI          = 'urn:ietf:wg:oauth:2.0:oob'

RAW_DIR      = File.join(__dir__, 'data', 'raw')
LOOKBACK_DAYS = 1
MAX_RESULTS   = 50

# Add sender email addresses to filter on. At least one required.
SENDER_FILTER = [
  'TBD@example.com'
].freeze

def main
  FileUtils.mkdir_p(RAW_DIR)

  service = Google::Apis::GmailV1::GmailService.new
  service.authorization = authorize

  query = build_query
  puts "Fetching emails with query: #{query}"

  messages = fetch_messages(service, query)
  if messages.empty?
    puts "No messages found matching criteria."
    exit 0
  end

  puts "Found #{messages.size} messages. Processing..."

  processed = 0
  messages.each do |msg|
    processed += 1 if store_message(service, msg.id)
  end

  puts "Fetch complete. #{processed}/#{messages.size} messages stored in #{RAW_DIR}"
end

def authorize
  client_id   = Google::Auth::ClientId.from_file(CREDENTIALS_PATH)
  token_store = Google::Auth::Stores::FileTokenStore.new(file: TOKEN_PATH)
  authorizer  = Google::Auth::UserAuthorizer.new(client_id, SCOPE, token_store)
  user_id     = 'default'

  credentials = authorizer.get_credentials(user_id)
  if credentials.nil?
    url = authorizer.get_authorization_url(base_url: OOB_URI)
    puts "Open this URL in your browser and authorize the app:"
    puts url
    puts "\nPaste the authorization code here:"
    code        = $stdin.gets.chomp
    credentials = authorizer.get_and_store_credentials_from_code(
      user_id: user_id, code: code, base_url: OOB_URI
    )
  end

  credentials
end

def build_query
  after_date    = (Date.today - LOOKBACK_DAYS).strftime('%Y/%m/%d')
  sender_clause = SENDER_FILTER.map { |s| "from:#{s}" }.join(' OR ')
  "#{sender_clause} after:#{after_date}"
end

def fetch_messages(service, query)
  result = service.list_user_messages('me', q: query, max_results: MAX_RESULTS)
  result.messages || []
rescue => e
  puts "Error fetching message list: #{e.message}"
  []
end

def store_message(service, message_id)
  msg = service.get_user_message('me', message_id, format: 'full')

  headers  = msg.payload.headers
  sender   = header_value(headers, 'From')
  subject  = header_value(headers, 'Subject')
  date_str = header_value(headers, 'Date')
  date     = parse_date(date_str)
  body     = extract_body(msg.payload)

  filename  = build_filename(date, subject)
  file_path = File.join(RAW_DIR, filename)

  File.write(file_path, build_markdown(sender, subject, date, message_id, body))
  puts "Stored: #{filename}"
  true
rescue => e
  puts "Error storing message #{message_id}: #{e.message}"
  false
end

def header_value(headers, name)
  headers.find { |h| h.name == name }&.value || ''
end

def parse_date(date_str)
  Date.parse(date_str)
rescue
  Date.today
end

def extract_body(payload)
  if payload.body&.data && !payload.body.data.empty?
    decode_body(payload.body.data)
  elsif payload.parts
    text_part = payload.parts.find { |p| p.mime_type == 'text/plain' }
    text_part&.body&.data ? decode_body(text_part.body.data) : '[No plain text body found]'
  else
    '[No body found]'
  end
end

def decode_body(data)
  Base64.urlsafe_decode64(data)
       .force_encoding('UTF-8')
       .encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
end

def build_filename(date, subject)
  prefix    = date.strftime('%Y%m%d')
  sanitized = sanitize_filename(subject)
  "#{prefix}_#{sanitized}.md"
end

def sanitize_filename(text)
  sanitized = text.gsub(/[^a-zA-Z0-9_\-]/, '_').downcase
  sanitized.gsub!(/_+/, '_')
  sanitized.gsub!(/^_|_$/, '')
  sanitized[0..80]
end

def build_markdown(sender, subject, date, message_id, body)
  <<~MARKDOWN
    ---
    sender: #{sender}
    subject: #{subject}
    date: #{date}
    message_id: #{message_id}
    ---

    #{body}
  MARKDOWN
end

main if __FILE__ == $PROGRAM_NAME
