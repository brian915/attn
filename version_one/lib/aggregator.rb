# frozen_string_literal: true

class Aggregator
  def initialize(config, verbose = false)
    @config = config
    @verbose = verbose
    @ranking = config['ranking'] || {}
  end

  def rank(summaries)
    puts "Ranking #{summaries.size} summaries" if @verbose

    scored = summaries.map { |s| score_summary(s) }
    ranked = scored.sort_by { |s| -s[:score] }

    top_count = @ranking['top_count'] || 5
    top_stories = ranked.take(top_count)

    puts "Top #{top_stories.size} stories selected" if @verbose
    top_stories
  end

  private

  def score_summary(summary)
    score = 0

    sender_weight = @ranking['sender_weights'] || {}
    from = summary[:from] || ''
    sender_weight.each do |sender, weight|
      score += weight.to_f if from.include?(sender)
    end

    keywords = @ranking['keyword_bonus'] || {}
    subject = summary[:subject] || ''
    body = summary[:summary] || ''
    content = "#{subject} #{body}".downcase

    keywords.each do |keyword, bonus|
      score += bonus.to_f if content.include?(keyword.downcase)
    end

    has_attachments = summary[:has_attachments]
    score += @ranking['attachment_bonus'].to_f if has_attachments

    recency_hours = (Time.now - Time.parse(summary[:summarized_at])).to_i / 3600
    recency_bonus = @ranking['recency_bonus'] || 0.1
    score += [recency_hours * recency_bonus, 2].min

    score += @ranking['length_bonus'].to_f if body.length > 200

    summary.merge(score: score)
  end
end
