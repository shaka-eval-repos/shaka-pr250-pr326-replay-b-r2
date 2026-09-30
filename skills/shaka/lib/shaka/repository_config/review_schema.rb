# frozen_string_literal: true

require_relative '../error'
require_relative '../reviewer_selection'
require_relative 'validation'

module Shaka
  class RepositoryConfig
    # Validates the ordered reviewer preference list and trigger policy.
    class ReviewSchema
      include Validation

      # The validator enforces exactly what selection consumes, so both read one definition.
      IDENTITY = ReviewerSelection::IDENTITY
      CI_REVIEW_JOBS = 'ci_review_jobs'
      LOCAL_REVIEW_AGENTS = 'local_review_agents'
      PROMPT_FILE = 'prompt_file'
      MODEL = 'model'
      EFFORT = 'effort'
      # Codex reads the effort as configuration text, and every reviewer repeats it in the attestation.
      EFFORT_LEVEL = /\A[a-z][a-z-]*\z/
      RENAMED = {
        'pace' => 'ci_review_wait',
        'ci_review_agents' => CI_REVIEW_JOBS,
        'check' => CI_REVIEW_JOBS,
        'github_action_check' => CI_REVIEW_JOBS,
        'reviewers' => LOCAL_REVIEW_AGENTS,
        'local_reviewers' => LOCAL_REVIEW_AGENTS
      }.freeze
      RETIRED = %w[model_family provider draft].freeze

      # The flat metadata group became an ordered list, so name the migration rather than
      # reporting an unknown key at a seam the previous release accepted.
      def self.retired!(review)
        found = RETIRED & review.keys
        return if found.empty?

        raise Error,
              "review.#{found.first} moved into review.#{LOCAL_REVIEW_AGENTS}; see skills/shaka/references/migration.md"
      end

      # `check` and `reviewers` did not say which list was the GitHub Action and which was local.
      def self.renamed!(review)
        old = RENAMED.keys.find { |key| review.key?(key) }
        return unless old

        raise Error, "review.#{old} moved to review.#{RENAMED.fetch(old)}; see skills/shaka/references/migration.md"
      end

      def self.effort_level!(value, label)
        return if value.is_a?(String) && value.match?(EFFORT_LEVEL)

        raise Error, "#{label} must be a level name such as medium"
      end

      # The model is passed to the reviewer CLI as one argument.
      def self.model_name!(value, label)
        raise Error, "#{label} must be a non-empty string" unless value.is_a?(String) && !value.strip.empty?
        raise Error, "#{label} must not contain whitespace" if value.match?(/\s/)
      end

      # Every prompt file the review section names, repository-wide and per reviewer.
      def self.prompt_files(review)
        agents = Array(review[LOCAL_REVIEW_AGENTS])
        ([["review.#{PROMPT_FILE}", review[PROMPT_FILE]]] +
          agents.each_with_index.map do |entry, index|
            ["review.#{LOCAL_REVIEW_AGENTS}[#{index}].#{PROMPT_FILE}", entry[PROMPT_FILE]]
          end).select { |_, path| path }
      end

      def initialize(review)
        @review = review
      end

      # A seam with no native gate still declares its reviewer order, because
      # `required: none` drops the repository's named check, not the alternate-review baseline.
      def validate
        enum!(@review['required'])
        validate_check
        validate_review_wait
        positive_integer!(@review.fetch('local_review_count', 1), 'review.local_review_count')
        local_review_agents!(@review[LOCAL_REVIEW_AGENTS]) if @review.key?(LOCAL_REVIEW_AGENTS)
        prompt_path!(@review[PROMPT_FILE], "review.#{PROMPT_FILE}") if @review.key?(PROMPT_FILE)
      end

      private

      def enum!(value)
        allowed = %w[always meaningful_changes none]
        super(value, allowed, 'review.required must be always, meaningful_changes, or none')
      end

      def validate_check
        label = "review.#{CI_REVIEW_JOBS}"
        return omitted_check!(label) if @review['required'] == 'none'

        name_list!(@review[CI_REVIEW_JOBS], label, 'CI job names')
      end

      def omitted_check!(label)
        return unless @review.key?(CI_REVIEW_JOBS)

        raise Error, "#{label} must be omitted when review.required is none"
      end

      def validate_review_wait
        return unless @review.key?('ci_review_wait')
        return if %w[none one all].include?(@review['ci_review_wait'])

        raise Error, 'review.ci_review_wait must be none, one, or all'
      end

      def local_review_agents!(reviewers)
        label = "review.#{LOCAL_REVIEW_AGENTS}"
        raise Error, "#{label} must be a list" unless reviewers.is_a?(Array)
        raise Error, "#{label} must not be empty" if reviewers.empty?

        reviewers.each_with_index { |entry, index| entry!(entry, index) }
        repeated!(reviewers)
      end

      # Selection folds case when it compares identities, so two spellings of one identity must
      # not both validate here.
      def repeated!(reviewers)
        identities = reviewers.map { |entry| entry.values_at(*IDENTITY).map(&:downcase) }
        repeated = identities.tally.find { |_, count| count > 1 }
        raise Error, "review.#{LOCAL_REVIEW_AGENTS} repeats #{repeated.first.join('/')}" if repeated
      end

      def entry!(entry, index)
        label = "review.#{LOCAL_REVIEW_AGENTS}[#{index}]"
        mapping!(entry, label)
        keys!(entry, IDENTITY, [PROMPT_FILE, MODEL, EFFORT], label)
        IDENTITY.each { |key| component!(entry[key], "#{label}.#{key}") }
        prompt_path!(entry[PROMPT_FILE], "#{label}.#{PROMPT_FILE}") if entry.key?(PROMPT_FILE)
        self.class.model_name!(entry[MODEL], "#{label}.#{MODEL}") if entry.key?(MODEL)
        self.class.effort_level!(entry[EFFORT], "#{label}.#{EFFORT}") if entry.key?(EFFORT)
      end

      # `shaka reviewer` reads identities as PROVIDER/MODEL_FAMILY and strips each part, so a
      # padded or slash-bearing value here would not match the identity the agent passes and a
      # contributing family could pass as eligible.
      def component!(value, label)
        string!(value, label)
        raise Error, "#{label} must not contain '/'" if value.include?('/')
        raise Error, "#{label} must not start or end with whitespace" if value != value.strip
      end
    end
  end
end
