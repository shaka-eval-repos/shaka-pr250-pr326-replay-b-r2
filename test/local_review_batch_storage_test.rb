# frozen_string_literal: true

require_relative 'local_review_batch_fixture'

class LocalReviewBatchStorageTest < Minitest::Test
  include LocalReviewBatchFixture

  def test_a_peer_disposition_written_during_review_survives_completion
    with_batch do
      successful_review('openai/codex')
      worker = Thread.new { review('anthropic/claude', barrier: true) }
      wait_ready('anthropic')
      record_round(1, summary: 'preserved disposition')
      release
      assert_worker_completed(worker)
      assert_first_summary('preserved disposition')
      assert_equal 2, ledger.fetch('rounds').size
    end
  end

  def test_cached_record_cannot_overwrite_new_disposition
    with_batch do
      successful_review('openai/codex')
      stale = Shaka::LocalReviewLedger.new(@ledger)
      stale.rounds
      record_round(1, summary: 'new disposition')
      assert_raises(Shaka::Error) { stale.record!('findings' => []) }
      assert_first_summary('new disposition')
    end
  end

  def test_cannot_rewrite_a_closed_batch_after_advancing
    with_batch do
      successful_review('openai/codex', count: 0)
      next_head
      successful_review('openai/codex', count: 0)
      before = ledger
      store = Shaka::LocalReviewLedger.new(@ledger)
      assert_raises(Shaka::Error) { store.record!('round' => 1, 'findings' => []) }
      assert_equal before, ledger
    end
  end

  def test_missing_round_and_mismatched_identity_do_not_modify_the_ledger
    with_batch do
      successful_review('openai/codex', count: 0)
      before = ledger
      [{ 'round' => 0 }, { 'round' => 2 }, { 'round' => '1' }, { 'head' => @base },
       { 'reviewer' => 'anthropic/claude' }].each do |content|
        assert_raises(Shaka::Error) { Shaka::LocalReviewLedger.new(@ledger).record!(content) }
      end
      assert_equal before, ledger
    end
  end

  def test_replaced_observed_history_is_rejected_without_erasing_replacement
    with_batch do
      successful_review('openai/codex', count: 0)
      worker = Thread.new { review('anthropic/claude', barrier: true, count: 0) }
      wait_ready('anthropic')
      replacement = replace_observed_history
      release
      assert_worker_stale(worker)
      assert_equal replacement, ledger
    end
  end

  private

  def assert_worker_completed(worker)
    result, status, error = worker.value
    assert_predicate status, :success?, "#{result}\n#{error}"
  end

  def assert_worker_stale(worker)
    result, status, = worker.value
    refute_predicate status, :success?
    assert_includes result.fetch('reason'), 'stale'
  end

  def assert_first_summary(summary)
    assert_equal summary, ledger.fetch('rounds').first.fetch('findings').first.fetch('summary')
  end

  def replace_observed_history
    replacement = ledger
    replacement['rounds'].first['reviewer'] = 'xai/grok'
    File.write(@ledger, JSON.generate(replacement))
    replacement
  end
end
