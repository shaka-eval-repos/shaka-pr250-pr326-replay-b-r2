# frozen_string_literal: true

require_relative 'local_review_batch_fixture'

class LocalReviewBatchConcurrencyTest < Minitest::Test
  include LocalReviewBatchFixture

  def test_concurrent_completions_and_dispositions_preserve_both_reviews
    with_batch do
      results = concurrent_reviews
      assert_peer_results(results)
      concurrent_dispositions
      next_head
      successful_review('openai/codex', count: 0)
      prompt = File.read(File.join(@directory, 'openai.prompt'))
      assert_includes prompt, 'finding 1'
      assert_includes prompt, 'finding 2'
    end
  end

  def test_duplicate_race_keeps_the_first_valid_result
    with_batch do
      workers = %w[first second].map do |label|
        Thread.new { review('openai/codex', label:, barrier: true, count: 0) }
      end
      wait_ready('first', 'second')
      release
      results = workers.map(&:value)
      assert_equal(1, results.count { |_, status,| status.success? })
      assert_equal 1, ledger.fetch('rounds').size
    end
  end

  def test_ledger_advancing_while_a_peer_runs_rejects_the_stale_result
    with_batch do
      successful_review('openai/codex', count: 0)
      worker = Thread.new { review('anthropic/claude', barrier: true, count: 0) }
      wait_ready('anthropic')
      changed = advance_ledger
      release
      assert_stale_result(worker.value)
      assert_equal changed, ledger
    end
  end

  def test_checkout_moving_during_review_does_not_append_a_stale_result
    with_batch do
      worker = Thread.new { review('openai/codex', barrier: true, count: 0) }
      wait_ready('openai')
      next_head
      release
      result, status, = worker.value
      refute_predicate status, :success?
      assert_includes result.fetch('reason'), 'Checkout HEAD'
      refute_path_exists @ledger
    end
  end

  private

  def concurrent_reviews
    workers = %w[openai/codex anthropic/claude].map { |id| Thread.new { review(id, barrier: true) } }
    wait_ready('openai', 'anthropic')
    release
    workers.map(&:value)
  end

  def assert_peer_results(results)
    results.each { |result, status, error| assert_predicate status, :success?, "#{result}\n#{error}" }
    assert_equal [1, 2], results.map { |result,| result.fetch('round') }.sort
    assert_equal %w[anthropic/claude openai/codex], ledger.fetch('rounds').map { |round| round.fetch('reviewer') }.sort
  end

  def concurrent_dispositions
    [1, 2].map { |number| Thread.new { record_round(number, summary: "finding #{number}") } }.each(&:value)
    summaries = ledger.fetch('rounds').map { |round| round.fetch('findings').first['summary'] }
    assert_equal ['finding 1', 'finding 2'], summaries
  end

  def assert_stale_result(result)
    review_result, status, = result
    refute_predicate status, :success?
    assert_includes review_result.fetch('reason'), 'stale'
    assert_equal 'ledger_update', review_result.fetch('failure_stage')
    assert_path_exists review_result.fetch('report')
  end

  def advance_ledger
    changed = ledger
    changed['rounds'] << changed['rounds'].first.merge('head' => 'f' * 40)
    File.write(@ledger, JSON.generate(changed))
    changed
  end
end
