# frozen_string_literal: true

require 'time'

module Attn
  class Runner
    def initialize(config_path: nil, logger: $stdout, now: Time.now.utc)
      @config_path = config_path
      @logger = logger
      @now = now
    end

    def run
      config = Attn::Config.load(@config_path)
      run_id = @now.utc.strftime('%Y%m%dT%H%M%SZ')

      storage = Attn::Storage.new(config.dig('output', 'base_dir'))
      run_paths = storage.prepare_run(run_id)

      manifest = build_initial_manifest(run_id, config, run_paths)
      behavior_config = config['behavior'] || {}

      begin
        gmail_client = Attn::GmailClient.new(config['gmail'], logger: @logger, now: @now)
        summarizer = Attn::Summarizer.new(config['llm'], logger: @logger)
        ranker = Attn::Ranker.new(config['ranking'], logger: @logger, now: @now)
        renderer = Attn::DigestRenderer.new

        fetched_messages = gmail_client.fetch_messages
        manifest['counts']['fetched'] = fetched_messages.length

        storage.write_records(fetched_messages, run_paths['records_dir'])

        processed_ids = storage.load_processed_ids
        new_messages = fetched_messages.reject do |message|
          processed_ids.include?(message['gmail_message_id'])
        end

        manifest['counts']['new'] = new_messages.length
        manifest['counts']['deduped'] = fetched_messages.length - new_messages.length

        summary_records = summarize_messages(new_messages, summarizer, storage, run_paths)
        manifest['counts']['summarized'] = summary_records.length

        ranker.apply_scores(summary_records)
        top_n = config.dig('ranking', 'top_n').to_i
        top_n = 5 if top_n <= 0

        top_stories = ranker.select_top_stories(summary_records, summarizer: summarizer, top_n: top_n)

        digest_content = renderer.render_digest(
          run_context: {
            'run_id' => run_id,
            'generated_at' => Time.now.utc.iso8601
          },
          top_stories: top_stories,
          all_summaries: summary_records
        )

        digest_filename = config.dig('output', 'digest_filename').to_s
        digest_filename = 'digest.md' if digest_filename.empty?

        digest_path = storage.write_digest(digest_content, run_paths['digest_dir'], digest_filename)

        manifest['status'] = 'success'
        manifest['paths']['digest_path'] = digest_path

        storage.append_processed_ids(new_messages.map { |message| message['gmail_message_id'] })

        @logger.puts(digest_content)
      rescue StandardError => error
        manifest['status'] = 'partial_failure'
        manifest['errors'] << error.message
        @logger.puts("Run failed: #{error.message}")
        raise error unless behavior_config['continue_on_api_error']
      ensure
        manifest['finished_at'] = Time.now.utc.iso8601
        storage.write_manifest(manifest, run_paths['manifest_path'])
      end

      true
    end

    private

    def summarize_messages(new_messages, summarizer, storage, run_paths)
      summary_records = []
      new_messages.each do |message|
        summary_data = summarizer.summarize_message(message)
        summary_record = {
          'gmail_message_id' => message['gmail_message_id'],
          'sender' => message['sender'],
          'subject' => message['subject'],
          'received_at' => message['received_at'],
          'summary_text' => summary_data['summary_text'],
          'why_it_matters' => summary_data['why_it_matters'],
          'key_signals' => summary_data['key_signals']
        }
        storage.write_summary(summary_record, run_paths['summaries_dir'])
        summary_records << summary_record
      end
      summary_records
    end

    def build_initial_manifest(run_id, config, run_paths)
      {
        'run_id' => run_id,
        'started_at' => Time.now.utc.iso8601,
        'status' => 'running',
        'counts' => { 'fetched' => 0, 'new' => 0, 'summarized' => 0 },
        'errors' => []
      }
    end
  end
end
