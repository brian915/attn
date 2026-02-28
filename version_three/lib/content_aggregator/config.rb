# frozen_string_literal: true

require 'yaml'

module ContentAggregator
  module Config
    module_function

    def load(config_path = nil)
      resolved_path = resolve_config_path(config_path)
      config_hash = File.exist?(resolved_path) ? YAML.safe_load(File.read(resolved_path)) : {}
      config_hash = {} unless config_hash.is_a?(Hash)

      defaults = default_config
      merged_config = deep_merge_hashes(defaults, config_hash)

      merged_config['meta'] ||= {}
      merged_config['meta']['resolved_config_path'] = resolved_path
      merged_config['output']['base_dir'] = resolve_output_dir(merged_config['output']['base_dir'])

      merged_config
    end

    def resolve_config_path(config_path)
      return File.expand_path(config_path, Dir.pwd) if config_path && !config_path.empty?

      from_environment = ENV['CONTENT_AGGREGATOR_CONFIG']
      return File.expand_path(from_environment, Dir.pwd) if from_environment && !from_environment.empty?

      File.expand_path('config/content_aggregator.yml', Dir.pwd)
    end

    def resolve_output_dir(path)
      return File.expand_path('output', Dir.pwd) if path.nil? || path.empty?

      File.expand_path(path, Dir.pwd)
    end

    def default_config
      {
        'gmail' => {
          'user_id' => 'me',
          'query_senders' => ['TBD@example.com'],
          'lookback_hours' => 24,
          'max_results' => 100
        },
        'output' => {
          'base_dir' => './output',
          'digest_filename' => 'digest.md'
        },
        'ranking' => {
          'top_n' => 5,
          'sender_priority' => {},
          'keywords' => ['breaking', 'launch', 'funding', 'security', 'incident']
        },
        'llm' => {
          'provider' => 'openai',
          'model' => 'TBD_MODEL',
          'temperature' => 0.2,
          'max_tokens' => 700,
          'timeout_seconds' => 60
        },
        'behavior' => {
          'continue_on_api_error' => true
        }
      }
    end

    def deep_merge_hashes(base_hash, override_hash)
      return base_hash unless override_hash.is_a?(Hash)

      merged_hash = base_hash.dup

      override_hash.each do |key, override_value|
        existing_value = merged_hash[key]

        if existing_value.is_a?(Hash) && override_value.is_a?(Hash)
          merged_hash[key] = deep_merge_hashes(existing_value, override_value)
        else
          merged_hash[key] = override_value
        end
      end

      merged_hash
    end
  end
end
