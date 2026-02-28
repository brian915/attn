# frozen_string_literal: true

require 'fileutils'
require 'date'

class Storage
  def initialize(base_dir, verbose = false)
    @base_dir = base_dir
    @verbose = verbose
    ensure_directories
  end

  def save_email(email)
    date = Date.today.strftime('%Y-%m-%d')
    email_dir = File.join(@base_dir, 'emails', date)
    FileUtils.mkdir_p(email_dir)

    filename = generate_filename(email)
    filepath = File.join(email_dir, filename)

    content = format_email_markdown(email)
    File.write(filepath, content)

    puts "Saved: #{filepath}" if @verbose

    email.merge({
      stored_path: filepath,
      filename: filename,
      stored_date: date,
      has_attachments: email[:has_attachments]
    })
  end

  def save_digest(content)
    digest_dir = File.join(@base_dir, 'digests')
    FileUtils.mkdir_p(digest_dir)

    date = Date.today.strftime('%Y-%m-%d')
    filename = "digest-#{date}.md"
    filepath = File.join(digest_dir, filename)

    File.write(filepath, content)
    puts "Saved digest: #{filepath}" if @verbose

    filepath
  end

  private

  def ensure_directories
    FileUtils.mkdir_p(File.join(@base_dir, 'emails'))
    FileUtils.mkdir_p(File.join(@base_dir, 'digests'))
    FileUtils.mkdir_p(File.join(@base_dir, 'summaries'))
  end

  def generate_filename(email)
    subject = email[:subject] || 'no-subject'
    subject = subject.gsub(/[^a-zA-Z0-9]/, '_')[0..50]
    sender = email[:from] || 'unknown'
    sender = sender.gsub(/[^a-zA-Z0-9]/, '_')[0..20]
    timestamp = Time.now.strftime('%Y%m%d-%H%M%S')

    "#{timestamp}_#{sender}_#{subject}.md"
  end

  def format_email_markdown(email)
    lines = []
    lines << "---"
    lines << "source: email"
    lines << "gmail_id: #{email[:gmail_id]}" if email[:gmail_id]
    lines << "from: #{email[:from]}"
    lines << "to: #{email[:to]}" if email[:to]
    lines << "subject: #{email[:subject]}"
    lines << "date: #{email[:date]}" if email[:date]
    lines << "retrieved_at: #{email[:retrieved_at]}"
    lines << "---"
    lines << ""
    lines << "# #{email[:subject]}"
    lines << ""
    lines << "**From:** #{email[:from]}"
    lines << ""
    lines << "**Date:** #{email[:date]}"
    lines << ""
    lines << "---"
    lines << ""
    lines << email[:body] || email[:snippet] || ""
    lines.join("\n")
  end
end
