# frozen_string_literal: true

require_relative 'reviewer_command_test'
require_relative 'repository_fixture'
require 'shaka/seam/field_classifier'
require 'shaka/reviewer_selection'
require 'shaka/repository_config'

class ReviewerCountSelectionTest < Minitest::Test
  ROSTER = %w[anthropic/claude openai/codex xai/grok].freeze

  def test_preserves_first_preference_then_uses_configured_order
    result = selection(3)
    assert_equal %w[openai/codex anthropic/claude xai/grok], result.fetch('reviewers')
    assert_equal 'openai/codex', result.fetch('reviewer')
    assert_equal 'different_provider', result.fetch('outcome')
    assert_equal selection(1).fetch('note'), result.fetch('note')
  end

  def test_skips_unavailable_and_deduplicates_case_folded_identities
    result = selection(10**100, unavailable: ['xai/grok'], roster: ROSTER + ['OpenAI/Codex'])
    assert_equal %w[openai/codex anthropic/claude], result.fetch('reviewers')
  end

  def test_fallback_remains_a_single_fresh_context
    result = selection(3, unavailable: ROSTER)
    assert_equal ['anthropic/claude'], result.fetch('reviewers')
    assert_equal 'same_model', result.fetch('outcome')
  end

  def test_rejects_invalid_counts_in_library
    [0, -1, '2', 1.5, nil, true].each do |count|
      assert_raises(Shaka::Error) { selection(count) }
    end
  end

  private

  def selection(count, unavailable: [], roster: ROSTER)
    Shaka::ReviewerSelection.new(reviewers: roster.map { |id| Shaka::ReviewerSelection.parse(id) },
                                 implementers: [Shaka::ReviewerSelection.parse('anthropic/claude')],
                                 unavailable: unavailable.map { |id| Shaka::ReviewerSelection.parse(id) }, count:).call
  end
end

# Reuse the command fixture to exercise real argument parsing and trusted config loading.
class ReviewerCommandTest
  def test_count_setting_and_override
    with_repository do |root|
      set_review_count(root, 2)
      assert_equal %w[openai/codex anthropic/claude], reviewer(root, '--implementer', 'anthropic/claude')['reviewers']
      assert_equal ['openai/codex'], reviewer(root, '--implementer', 'anthropic/claude', '--count', '1')['reviewers']
      commit_repository(root)
      set_review_count(root, 3)
      result = reviewer(root, '--ref', 'HEAD', '--implementer', 'anthropic/claude')
      assert_equal 2, result.fetch('reviewers').size
    end
  end

  def set_review_count(root, count)
    data = config
    data['review']['local_review_count'] = count
    File.write(File.join(root, '.agents/agent-workflow.yml'), YAML.dump(data))
  end

  def test_rejects_nonpositive_and_noninteger_count_options
    with_repository do |root|
      %w[0 -1 1.2 two +2].each do |value|
        _, error, status = Open3.capture3(COMMAND, 'reviewer', '--root', root,
                                          '--implementer', 'anthropic/claude', '--count', value)
        refute_predicate status, :success?
        assert_includes error, 'positive integer'
      end
    end
  end
end

class ReviewerCountSchemaTest < Minitest::Test
  include RepositoryConfigTestHelpers

  def test_default_and_configured_positive_count
    [{}, { 'local_review_count' => 3 }].each do |settings|
      with_repository('review' => review_policy(settings)) do |root|
        assert_equal settings.fetch('local_review_count', 1), Shaka::RepositoryConfig.load(root:).review['local_review_count']
      end
    end
  end

  def test_rejects_invalid_configuration_types_and_values
    [0, -1, '2', 1.5, nil, true].each do |value|
      with_repository('review' => review_policy('local_review_count' => value)) do |root|
        error = assert_raises(Shaka::Error) { Shaka::RepositoryConfig.load(root:) }
        assert_includes error.message, 'local_review_count must be a positive integer'
      end
    end
  end

  def test_migration_preserves_the_count
    data = { 'version' => 1, 'merge' => { 'preference' => 'ask' },
             'review' => { 'required' => 'none', 'local_review_count' => 2 } }
    result = Shaka::Seam::FieldClassifier.new(data).call
    assert_empty result.blocking
    assert_equal 2, result.established.dig('review', 'local_review_count')
  end
end
