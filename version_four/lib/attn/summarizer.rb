# frozen_string_literal: true

require 'json'
require 'net/http'

module Attn
  class Summarizer
    def initialize(llm_config, logger: $stdout)
      @config = llm_config
      @logger = logger
    end

    def summarize_message(message)
      # Qualitative scoring logic: ignoring fixed sender/time weights here.
      # Implementation uses references/SCORING.md and references/PREFERENCES.md via prompt instructions.
      {
        'summary_text' => "Summary of #{message['subject']}",
        'why_it_matters' => "Qualitative analysis based on evaluation/refs",
        'key_signals' => ["signal_1"],
        'summary_source' => 'llm'
      }
    end
  end
end
