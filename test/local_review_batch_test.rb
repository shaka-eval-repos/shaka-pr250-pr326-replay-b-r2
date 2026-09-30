# frozen_string_literal: true

require_relative 'local_review_batch_fixture'

class LocalReviewBatchTest < Minitest::Test
  include LocalReviewBatchFixture

  def test_same_head_peers_do_not_see_each_others_findings
    with_batch do
      successful_review('openai/codex')
      record_round(1)
      next_head
      successful_review('openai/codex')
      record_round(2, summary: 'current finding')
      successful_review('anthropic/claude')
      assert_isolated_prompt
      assert_equal 3, ledger.fetch('rounds').size
    end
  end

  def test_new_head_waits_for_every_peer_disposition
    with_batch do
      successful_review('openai/codex')
      successful_review('anthropic/claude')
      record_round(2)
      previous = @head
      next_head
      assert_review_refused('Record round 1')
      record_previous_head(previous, 1)
      successful_review('openai/codex', count: 0)
    end
  end

  def test_duplicate_reviewer_and_changed_base_are_rejected
    with_batch do
      successful_review('openai/codex', count: 0)
      assert_review_refused('already reviewed')
      @base = @head
      assert_review_refused('measure the change', id: 'anthropic/claude')
      assert_equal 1, ledger.fetch('rounds').size
    end
  end

  def test_all_peer_fix_commits_must_be_in_the_next_head
    with_batch do
      successful_review('openai/codex')
      successful_review('anthropic/claude', count: 0)
      side = record_side_fix
      assert_review_refused("does not build on #{side}")
    end
  end

  private

  def record_previous_head(previous, number)
    current = @head
    @head = previous
    record_round(number)
    @head = current
  end

  def record_side_fix
    previous = @head
    git!(@root, 'checkout', '-b', 'side')
    next_head
    side = @head
    @head = previous
    record_round(1, class: 'defect', disposition: 'fixed', commit: side)
    git!(@root, 'checkout', '-')
    commit!(@root, 'unrelated change', 'Different fix')
    @head = git!(@root, 'rev-parse', 'HEAD').strip
    side
  end
end
