# frozen_string_literal: true

require_relative 'spec_helper'

class StorageTest < Minitest::Test
  def test_processed_ids_are_deduplicated_when_appended
    Dir.mktmpdir('content_aggregator_storage_test') do |temp_dir|
      storage = ContentAggregator::Storage.new(temp_dir)
      storage.prepare_run('run_for_storage_test')

      storage.append_processed_ids(['abc123', 'abc123', 'def456'])
      storage.append_processed_ids(['def456', 'ghi789'])

      processed_ids = storage.load_processed_ids

      assert_equal(Set.new(%w[abc123 def456 ghi789]), processed_ids)
    end
  end
end
