# frozen_string_literal: true

require_relative 'spec_helper'

class GmailClientTest < Minitest::Test
  def test_build_query_with_multiple_senders
    gmail_config = {
      'query_senders' => ['alerts@example.com', 'news@example.com'],
      'lookback_hours' => 24,
      'max_results' => 10,
      'user_id' => 'me'
    }

    fixed_time = Time.utc(2026, 2, 28, 12, 0, 0)
    client = ContentAggregator::GmailClient.new(gmail_config, now: fixed_time)

    query = client.build_query(senders: gmail_config['query_senders'], lookback_hours: 24)

    assert_includes(query, 'from:alerts@example.com')
    assert_includes(query, 'from:news@example.com')
    assert_includes(query, "after:#{(fixed_time - 86_400).to_i}")
  end
end
