# frozen_string_literal: true

require 'date'

class Formatter
  def initialize(verbose = false)
    @verbose = verbose
  end

  def format_digest(stories)
    lines = []
    lines << "# Daily Content Digest"
    lines << ""
    lines << "**Date:** #{Date.today.strftime('%Y-%m-%d')}"
    lines << ""
    lines << "**Top #{stories.size} Stories:**"
    lines << ""

    stories.each_with_index do |story, index|
      lines << format_story(story, index + 1)
      lines << ""
    end

    lines.join("\n")
  end

  private

  def format_story(story, index)
    lines = []
    lines << "### #{index}. #{story[:subject]}"
    lines << ""
    lines << "**From:** #{story[:from]}"
    lines << ""
    lines << story[:summary]
    lines << ""

    if story[:stored_path]
      relative_path = story[:stored_path].split('/data/').last
      lines << "[View original email](./#{relative_path})"
    end

    lines << ""
    lines << "*Score: #{story[:score].round(2)}*"

    lines.join("\n")
  end
end
