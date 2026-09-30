# frozen_string_literal: true

require 'json'
require_relative '../error'
require_relative 'evidence'
require_relative 'finding'
require_relative 'ledger_storage'

module Shaka
  # Private record of a local review loop: each round's commit, reviewer settings, report, and
  # what became of its findings. It stays outside the checkout until `review publish` renders it,
  # and it has the same shape as that command's content file.
  class LocalReviewLedger
    include LocalReviewLedgerStorage

    attr_reader :path

    # Only `review run` can start a ledger, so only it needs the checkout to keep the ledger out of.
    def initialize(path, root: nil)
      @path = File.expand_path(path)
      directory = File.realpath(File.dirname(@path))
      raise Error, '--ledger must be outside the candidate checkout' if
        root && (directory == root || directory.start_with?("#{root}/"))
    end

    def rounds = data.fetch('rounds')

    def last_round_fixes
      latest_batch.flat_map do |round|
        LocalReviewFinding.list(round['findings'], 'batch finding').select(&:fixed?).map(&:commit)
      end.uniq
    end

    def last_head = rounds.last&.fetch('head')

    # Different reviewers may join the latest head; a new head waits for all dispositions.
    def check_next!(base:, head:, reviewer: nil)
      return if rounds.empty?

      raise Error, "The ledger's rounds measure the change against #{data['base']}; use a new ledger." unless
        data['base'] == base

      check_new_head!(head, reviewer)
      return if head == last_head

      incomplete = rounds.index { |round| !recorded?(round) }
      return unless incomplete

      raise Error, "Record round #{incomplete + 1}'s findings with `shaka review record` before the next round."
    end

    # The newest disposition per reviewer and finding ID, excluding peers at the requested head.
    def prior_findings(head: nil)
      rounds.reject { |round| round['head'] == head }.each_with_index.with_object({}) do |(round, index), latest|
        LocalReviewFinding.list(round['findings'], "round #{index + 1} finding").each do |finding|
          latest[[round.fetch('reviewer').downcase, finding.id]] = finding
        end
      end.values
    end

    def append!(base:, round:)
      snapshot = data
      transaction do
        check_snapshot!(snapshot, round.fetch('head'))
        check_next!(base:, head: round.fetch('head'), reviewer: round.fetch('reviewer'))
        write(data.merge('base' => base, 'rounds' => rounds + [round]))
        rounds.size
      end
    end

    # Sets a named round, or the last observed round for single-reviewer callers.
    def record!(content)
      raise Error, 'Record content must be an object.' unless content.is_a?(Hash)

      number = record_number(content)
      original = rounds.fetch(number - 1)
      transaction do
        raise Error, 'The review ledger changed; disposition is stale.' unless rounds[number - 1] == original

        raise Error, 'Earlier batch dispositions are closed; use a new ledger to revise history.' if
          original.fetch('head') != last_head

        record_identity!(content, original, number)
        replace_round(content, original, number)
      end
    end

    def prior_head(head) = rounds.reverse.find { |round| round['head'] != head }&.fetch('head')

    private

    def record_number(content)
      number = content.fetch('round', rounds.size)
      raise Error, 'Record round must name an existing positive integer round.' unless
        number.is_a?(Integer) && number.positive? && number <= rounds.size

      number
    end

    def record_identity!(content, original, number)
      %w[head reviewer].each do |key|
        next unless content.key?(key) && content[key] != original[key]

        raise Error, "Record #{key} does not match round #{number}."
      end
    end

    def replace_round(content, original, number)
      round = original.merge(content.slice('findings', 'model', 'tokens', 'cost', 'estimate'))
      check_findings!(round, number)
      updated = rounds.dup
      updated[number - 1] = round
      write(data.merge(content.slice('fallback'), 'rounds' => updated))
      number
    end

    def check_new_head!(head, reviewer)
      reviewed = rounds.index do |round|
        round['head'] == head && (head != last_head || reviewer.nil? ||
          round.fetch('reviewer').downcase == reviewer.downcase)
      end
      raise Error, "Round #{reviewed + 1} already reviewed #{head}; commit the fix first." if reviewed
    end

    def latest_batch = rounds.select { |round| round['head'] == last_head }

    def recorded?(round)
      return reported_count(round).zero? unless round.key?('findings')

      check_findings!(round, rounds.index(round) + 1)
      true
    end

    # The count check keeps a finding from dropping out between the report and the comment.
    def check_findings!(round, number)
      findings = LocalReviewFinding.list(round['findings'], "round #{number} finding")
      reported = reported_count(round)
      return if findings.size == reported

      raise Error, "Round #{number}'s report counts #{reported} findings; #{findings.size} were recorded."
    end

    def reported_count(round)
      match = File.read(round.fetch('report'), encoding: 'UTF-8').match(LocalReviewEvidence::CLOSING)
      raise Error, "Round report #{round['report']} has no FINDINGS count." unless match

      match[2].to_i
    end
  end
end
