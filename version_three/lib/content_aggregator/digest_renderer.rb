# frozen_string_literal: true

module ContentAggregator
  class DigestRenderer
    def render_digest(run_context:, top_stories:, all_summaries:)
      digest_lines = []
      digest_lines << "# Daily Content Digest"
      digest_lines <<
        "Generated: #{run_context['generated_at']} | Run ID: #{run_context['run_id']} | Total New Summaries: #{all_summaries.length}"
      digest_lines << ''
      digest_lines << '## Top Stories'

      if top_stories.empty?
        digest_lines << '- No top stories found for this run.'
      else
        top_stories.each_with_index do |story, index|
          digest_lines.concat(render_top_story_block(story, index + 1))
        end
      end

      digest_lines << ''
      digest_lines << '## All Summaries'

      if all_summaries.empty?
        digest_lines << '- No new summaries generated in this run.'
      else
        all_summaries.each do |summary|
          digest_lines << "- [#{summary['subject']}](#{summary['summary_file_path']})"
        end
      end

      digest_lines << ''
      digest_lines << '## Notes'
      digest_lines << '- Summary serving interface: TBD'
      digest_lines << '- Digest auto-send: deferred in v0'

      digest_lines.join("\n")
    end

    private

    def render_top_story_block(story, rank_number)
      lines = []
      lines << "### #{rank_number}. #{story['subject']}"
      lines << "- Sender: #{story['sender']}"
      lines << "- Received At: #{story['received_at']}"
      lines << "- Rank Score: #{format('%.3f', story['rank_score'].to_f)}"
      lines << "- Why It Matters: #{story['why_it_matters']}"
      lines << "- Summary Link: [Open Summary](#{story['summary_file_path']})"
      lines << ''
      lines
    end
  end
end
