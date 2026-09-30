# frozen_string_literal: true

require_relative 'test_helper'
require 'shaka/reviewer_selection'

# The replay starts with a missing ordered result, not an environment error.
class EvalOrderedReviewersTest < Minitest::Test
  def test_default_selection_reports_an_ordered_single_reviewer
    result = Shaka::ReviewerSelection.new(
      reviewers: [{ 'provider' => 'anthropic', 'model_family' => 'claude' },
                  { 'provider' => 'openai', 'model_family' => 'codex' }],
      implementers: [{ 'provider' => 'openai', 'model_family' => 'codex' }]
    ).call

    assert_equal 'anthropic/claude', result.fetch('reviewer')
    assert_equal ['anthropic/claude'], result['reviewers']
  end
end
