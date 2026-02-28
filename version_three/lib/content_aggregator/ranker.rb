# frozen_string_literal: true

require 'time'

module ContentAggregator
  class Ranker
    def initialize(ranking_config, logger: $stdout, now: Time.now.utc)
      @ranking_config = ranking_config
      @logger = logger
      @now = now
    end

    def apply_scores(summary_records)
      summary_records.each do |record|
        components = score_components(record)
        heuristic_score = components.values.sum

        record['score_components'] = components
        record['heuristic_score'] = heuristic_score.round(3)
        record['rank_score'] = record['heuristic_score']
      end
    end

    def select_top_stories(summary_records, summarizer:, top_n:)
      return [] if summary_records.empty?

      selected_by_llm = summarizer.rank_story_ids(summary_records, top_n.to_i)
      llm_boosts = build_llm_boosts(selected_by_llm)

      summary_records.each do |record|
        base_score = record['heuristic_score'].to_f
        llm_bonus = llm_boosts.fetch(record['gmail_message_id'], 0.0)

        record['rank_score'] = (base_score + llm_bonus).round(3)
        record['llm_bonus'] = llm_bonus.round(3)
      end

      sorted_records = summary_records.sort_by { |record| -record['rank_score'].to_f }
      sorted_records.first(top_n.to_i)
    end

    private

    def score_components(record)
      {
        'sender_priority' => sender_priority_score(record),
        'recency' => recency_score(record),
        'keyword_match' => keyword_score(record),
        'length_signal' => length_score(record)
      }
    end

    def sender_priority_score(record)
      sender_priorities = @ranking_config['sender_priority'] || {}
      sender = record['sender'].to_s.downcase

      sender_priorities.each do |key, value|
        return value.to_f if sender.include?(key.to_s.downcase)
      end

      0.0
    end

    def recency_score(record)
      received_at_text = record['received_at'].to_s
      received_at = Time.parse(received_at_text)
      age_hours = ((@now - received_at) / 3600.0)

      if age_hours <= 6
        2.0
      elsif age_hours <= 24
        1.0
      elsif age_hours <= 48
        0.4
      else
        0.1
      end
    rescue StandardError
      0.1
    end

    def keyword_score(record)
      keywords = Array(@ranking_config['keywords']).map { |item| item.to_s.downcase }.reject(&:empty?)
      return 0.0 if keywords.empty?

      text = [record['subject'], record['summary_text'], record['why_it_matters']].join(' ').downcase
      hits = keywords.count { |keyword| text.include?(keyword) }
      [hits * 0.5, 2.0].min
    end

    def length_score(record)
      summary_length = record['summary_text'].to_s.length
      return 0.1 if summary_length < 100
      return 0.4 if summary_length < 250

      0.7
    end

    def build_llm_boosts(selected_ids)
      boosts = {}
      list_size = selected_ids.length

      selected_ids.each_with_index do |message_id, index|
        position_bonus = (list_size - index).to_f / [list_size, 1].max
        boosts[message_id] = 1.2 + position_bonus
      end

      boosts
    end
  end
end
