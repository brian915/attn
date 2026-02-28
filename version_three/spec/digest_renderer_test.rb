# frozen_string_literal: true

require_relative 'spec_helper'

class DigestRendererTest < Minitest::Test
  def test_digest_contains_local_summary_links
    renderer = ContentAggregator::DigestRenderer.new

    summary_record = {
      'subject' => 'Product launch update',
      'sender' => 'team@example.com',
      'received_at' => '2026-02-28T09:00:00Z',
      'rank_score' => 3.2,
      'why_it_matters' => 'This affects our roadmap.',
      'summary_file_path' => '/tmp/summaries/message_1.md'
    }

    digest = renderer.render_digest(
      run_context: {
        'run_id' => 'test_run_1',
        'generated_at' => '2026-02-28T10:00:00Z'
      },
      top_stories: [summary_record],
      all_summaries: [summary_record]
    )

    assert_includes(digest, '[Open Summary](/tmp/summaries/message_1.md)')
    assert_includes(digest, '[Product launch update](/tmp/summaries/message_1.md)')
  end
end
