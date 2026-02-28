# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'set'

module Attn
  class Storage
    def initialize(base_dir)
      @base_dir = base_dir
      @state_dir = File.join(@base_dir, 'state')
      @processed_ids_path = File.join(@state_dir, 'processed_message_ids.txt')
    end

    def prepare_run(run_id)
      run_dir = File.join(@base_dir, 'runs', run_id)
      paths = {
        'run_dir' => run_dir,
        'records_dir' => File.join(run_dir, 'records'),
        'summaries_dir' => File.join(run_dir, 'summaries'),
        'digest_dir' => File.join(run_dir, 'digest'),
        'manifest_path' => File.join(run_dir, 'manifest.json'),
        'processed_ids_path' => @processed_ids_path
      }
      paths.each_value { |path| FileUtils.mkdir_p(File.dirname(path)) unless path.end_with?('.json', '.txt') }
      FileUtils.mkdir_p(paths['records_dir'])
      FileUtils.mkdir_p(paths['summaries_dir'])
      FileUtils.mkdir_p(paths['digest_dir'])
      paths
    end

    def write_records(messages, records_dir)
      messages.each do |msg|
        File.write(File.join(records_dir, "#{msg['gmail_message_id']}.json"), msg.to_json)
      end
    end

    def write_summary(summary, summaries_dir)
      File.write(File.join(summaries_dir, "#{summary['gmail_message_id']}.md"), summary['summary_text'])
    end

    def write_digest(content, digest_dir, filename)
      path = File.join(digest_dir, filename)
      File.write(path, content)
      path
    end

    def write_manifest(manifest, path)
      File.write(path, manifest.to_json)
    end

    def load_processed_ids
      File.exist?(@processed_ids_path) ? Set.new(File.readlines(@processed_ids_path).map(&:strip)) : Set.new
    end

    def append_processed_ids(ids)
      File.open(@processed_ids_path, 'a') { |f| ids.each { |id| f.puts(id) } }
    end
  end
end
