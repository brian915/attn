# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'set'

module ContentAggregator
  class Storage
    def initialize(base_dir)
      @base_dir = base_dir
      @state_dir = File.join(@base_dir, 'state')
      @processed_ids_path = File.join(@state_dir, 'processed_message_ids.txt')
    end

    def prepare_run(run_id)
      run_dir = File.join(@base_dir, 'runs', run_id)
      records_dir = File.join(run_dir, 'records')
      summaries_dir = File.join(run_dir, 'summaries')
      digest_dir = File.join(run_dir, 'digest')
      manifest_path = File.join(run_dir, 'manifest.json')

      [@base_dir, @state_dir, run_dir, records_dir, summaries_dir, digest_dir].each do |directory|
        FileUtils.mkdir_p(directory)
      end

      {
        'run_dir' => run_dir,
        'records_dir' => records_dir,
        'summaries_dir' => summaries_dir,
        'digest_dir' => digest_dir,
        'manifest_path' => manifest_path,
        'processed_ids_path' => @processed_ids_path
      }
    end

    def write_records(messages, records_dir)
      messages.each do |message|
        message_id = sanitize_filename_fragment(message['gmail_message_id'])
        file_path = File.join(records_dir, "message_#{message_id}.json")
        File.write(file_path, JSON.pretty_generate(message))
      end
    end

    def write_summary(summary_record, summaries_dir)
      message_id_fragment = sanitize_filename_fragment(summary_record['gmail_message_id'])
      subject_fragment = sanitize_filename_fragment(summary_record['subject']).slice(0, 80)
      file_name = "#{message_id_fragment}_#{subject_fragment}.md"
      file_path = File.join(summaries_dir, file_name)

      summary_record['summary_file_path'] = file_path
      markdown_text = build_summary_markdown(summary_record)
      File.write(file_path, markdown_text)
      file_path
    end

    def write_digest(markdown_text, digest_dir, digest_filename)
      file_path = File.join(digest_dir, digest_filename)
      File.write(file_path, markdown_text)
      file_path
    end

    def write_manifest(manifest_hash, manifest_path)
      File.write(manifest_path, JSON.pretty_generate(manifest_hash))
    end

    def load_processed_ids
      return Set.new unless File.exist?(@processed_ids_path)

      Set.new(File.readlines(@processed_ids_path, chomp: true).reject(&:empty?))
    end

    def append_processed_ids(message_ids)
      return if message_ids.empty?

      existing_ids = load_processed_ids
      new_ids = message_ids.map(&:to_s).reject(&:empty?).reject { |message_id| existing_ids.include?(message_id) }
      return if new_ids.empty?

      File.open(@processed_ids_path, 'a') do |file|
        new_ids.each { |message_id| file.puts(message_id) }
      end
    end

    private

    def build_summary_markdown(summary_record)
      <<~MARKDOWN
        ---
        gmail_message_id: #{summary_record['gmail_message_id']}
        summary_created_at: #{summary_record['summary_created_at']}
        source_record_path: #{summary_record['source_record_path']}
        sender: #{summary_record['sender']}
        subject: #{summary_record['subject']}
        heuristic_score: #{format('%.3f', summary_record['heuristic_score'].to_f)}
        rank_score: #{format('%.3f', summary_record['rank_score'].to_f)}
        ---

        # Summary
        #{summary_record['summary_text']}

        # Why It Matters
        #{summary_record['why_it_matters']}

        # Key Signals
        #{format_key_signals(summary_record['key_signals'])}

        # Metadata
        - Received At: #{summary_record['received_at']}
        - Summary File: #{summary_record['summary_file_path']}
      MARKDOWN
    end

    def format_key_signals(key_signals)
      safe_signals = Array(key_signals).map(&:to_s).reject(&:empty?)
      return '- TBD' if safe_signals.empty?

      safe_signals.map { |signal| "- #{signal}" }.join("\n")
    end

    def sanitize_filename_fragment(text)
      value = text.to_s.downcase
      value = value.gsub(/[^a-z0-9]+/, '_')
      value = value.gsub(/_+/, '_').gsub(/^_/, '').gsub(/_$/, '')
      value = 'item' if value.empty?
      value
    end
  end
end
