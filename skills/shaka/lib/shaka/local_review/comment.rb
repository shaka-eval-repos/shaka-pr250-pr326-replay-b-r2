# frozen_string_literal: true

require 'cgi'
require_relative '../error'
require_relative '../publication/publication'
require_relative '../reviewer_selection'
require_relative 'evidence'
require_relative 'finding'
require_relative 'summary'

module Shaka
  # Renders one pull request comment for a local adversarial review: a summary a reader skims,
  # each report and what became of its findings collapsed beneath it, and the last round's
  # attestation as the closing line, which is where `merge` reads review evidence.
  class LocalReviewComment
    KEY = 'local-adversarial-review'
    TITLE = '# Local Adversarial Review'
    COLUMNS = %w[Round Commit Reviewer Model Effort Prompt Findings Tokens Cost].freeze
    OUTCOMES = %w[different_provider same_provider same_model].freeze
    SETUP_GUIDE = 'https://github.com/shakacode/shaka/blob/main/docs/settings.md#add-a-second-reviewer'
    CLOSING = LocalReviewEvidence::CLOSING
    # A setup failure's reason can name a file on the reviewer's machine; a public PR must not show it.
    # A path can contain spaces, so everything from its first character on is dropped.
    LOCAL_PATH = %r{(?<![\w./-])(?:~|/).*}m
    def self.render(content) = new(content).render

    # With the pull request's `repository`, each commit links to GitHub; `published` answers whether
    # GitHub has a commit, so one lost to a rebase is named without a broken link.
    def initialize(content, repository: nil, published: nil)
      raise Error, 'Local review content must be an object.' unless content.is_a?(Hash)
      raise Error, 'Expected a GitHub repository in OWNER/REPO form.' unless
        repository.nil? || repository.match?(%r{\A[\w-]+/[\w.-]+\z})

      @links = LocalReviewLinks.new(repository, published)
      @rounds = build_rounds(PublicationText.list(content['rounds'], 'rounds'))
      @fallback = content['fallback']
    end

    def render
      blocks = [TITLE, table, *LocalReviewSummary.new(@rounds).lines, *fallback_notice, *round_details,
                @rounds.last.attestation]
      "#{blocks.join("\n\n")}\n"
    end

    # Reports are published verbatim, so a stray fence or disclosure tag in one can swallow the rest
    # of the comment. GitHub's own rendering decides that; a regex over Markdown cannot.
    def check_rendering!(html)
      closing = %r{<p\b[^>]*>#{Regexp.escape(CGI.escapeHTML(@rounds.last.attestation))}</p>\s*\z}
      disclosures = [html.scan(/<details\b/).size, html.scan('</details>').size]
      return if html.match?(closing) && disclosures == [@rounds.size] * 2 && summaries_in_order?(html)

      raise Error, 'A review report leaves its markup open or adds disclosure tags, so GitHub would not show ' \
                   'each round collapsed with the attestation last. Fix the report and publish again.'
    end

    private

    # A fix is evidence only once a later round has reviewed a new head. Without git, only these
    # structural checks apply; `review run --ledger` checks the history itself.
    def build_rounds(specs)
      raise Error, 'Local review content needs at least one round.' if specs.empty?

      rounds = specs.each_with_index.map { |round, index| Round.new(round, index + 1) }
      check_order!(rounds)
      rounds
    end

    def check_order!(rounds)
      identities = rounds.map { |round| [round.head, round.reviewer] }
      raise Error, 'Two rounds review the same commit with the same reviewer.' unless identities.uniq == identities

      check_batches!(rounds)
      check_final_batch!(rounds)
      rounds.each(&:check_fixes_follow!)
    end

    def check_batches!(rounds)
      heads = rounds.chunk(&:head).map(&:first)
      raise Error, 'A batch returns to an earlier head.' unless heads.uniq == heads
    end

    def check_final_batch!(rounds)
      final_batch = rounds.select { |round| round.head == rounds.last.head }
      findings = final_batch.flat_map(&:findings)
      raise Error, "Round #{rounds.size} records fixes no later round reviewed; review the fix head first." if
        findings.any?(&:fixed?)
    end

    # A fence opened in one report and closed in the next hides the boundary between them, including
    # the next round's own summary; balanced tags the reports supply cannot stand in for it.
    def summaries_in_order?(html)
      offset = 0
      @rounds.all? do |round|
        found = html.index("<summary>#{round.summary}</summary>", offset)
        offset = found + 1 if found
      end
    end

    # A finding whose id was marked fixed in an earlier round and comes back is flagged where it returns.
    def round_details
      fixed = {}
      @rounds.map do |round|
        reviewer_fixes = (fixed[round.reviewer] ||= {})
        text = round.details(@links, reviewer_fixes)
        round.findings.select(&:fixed?).each { |finding| reviewer_fixes[finding.id] = finding.commit }
        text
      end
    end

    def table
      rows = @rounds.map { |round| line(round.cells(@links)) }
      [line(COLUMNS), line(['---'] * COLUMNS.size), *rows].join("\n")
    end

    # Escaping backslashes first keeps a supplied `\|` from ending its cell early.
    def line(cells) = "| #{cells.map { |cell| cell.gsub(/[\\|]/) { |char| "\\#{char}" } }.join(' | ')} |"

    def fallback_notice
      return [] if @fallback.nil?
      raise Error, 'Local review fallback must be an object.' unless @fallback.is_a?(Hash)

      outcome = @fallback['outcome']
      raise Error, "Local review fallback outcome must be one of #{OUTCOMES.join(', ')}." unless
        OUTCOMES.include?(outcome)
      return [] if outcome == 'different_provider'

      [(['**Reviewer fallback:** no reviewer from a different provider ran, so this review ' \
         "used `#{outcome}`. [Add a second reviewer](#{SETUP_GUIDE}) to avoid this."] + attempts).join("\n")]
    end

    # Selection can fall back without trying anything, as when no other provider is configured.
    def attempts
      tried = PublicationText.list(@fallback['attempts'], 'fallback attempts')
      return [] if tried.empty?

      ['', 'Tried:', ''] + tried.map { |attempt| attempt_line(attempt) }
    end

    def attempt_line(attempt)
      raise Error, 'Each fallback attempt must be an object.' unless attempt.is_a?(Hash)

      reviewer = PublicationText.single_line(attempt['reviewer'], 'fallback reviewer')
      stage = PublicationText.single_line(attempt['failure_stage'], 'fallback failure_stage')
      reason = PublicationText.single_line(attempt['reason'], 'fallback reason').sub(LOCAL_PATH, '[path]')
      "- `#{reviewer}`: `#{stage}`: #{reason}"
    end

    # One reviewed commit, its reviewer settings, and the report whose attestation it carries.
    class Round
      attr_reader :head, :findings, :reviewer

      def initialize(spec, number)
        raise Error, "Local review round #{number} must be an object." unless spec.is_a?(Hash)

        @spec = spec
        @number = number
        @head = spec['head'].to_s
        raise Error, "Round #{number} head must be a full commit SHA." unless @head.match?(LocalReviewEvidence::SHA)

        # Parsed as `merge` parses it, so a comment merge would ignore is never published.
        @reviewer = ReviewerSelection.parse(field('reviewer')).values.map(&:downcase).join('/')
        @report = read_report
        @findings = LocalReviewFinding.list(spec['findings'], "round #{number} finding")
        check_count!
      end

      def cells(links)
        effort, findings = @report.match(CLOSING).captures
        [@number.to_s, links.commit(@head), @reviewer, optional('model'), effort, prompt(links),
         findings + outcome, optional('tokens'), cost]
      end

      # A supplied single-line value, or nil when the round leaves it out.
      def value(name) = (field(name) unless @spec[name].nil? || @spec[name].to_s.strip.empty?)

      def summary
        effort, findings = @report.match(CLOSING).captures
        noun = findings == '1' ? 'finding' : 'findings'
        PublicationText.summary_text("Round #{@number} · #{@head[0, 7]} · #{@reviewer} · " \
                                     "effort #{effort} · #{findings} #{noun}", 'round summary')
      end

      def details(links, fixed_before = {})
        "<details>\n<summary>#{summary}</summary>\n\n#{@report.strip}\n\n" \
          "#{dispositions(links, fixed_before)}</details>"
      end

      def attestation = @report.strip.lines.last.strip

      def check_fixes_follow!
        return unless @findings.any? { |finding| finding.fixed? && finding.commit == @head }

        raise Error, "Round #{@number} records a fix in the commit it reviewed; commit the fix."
      end

      private

      # Every finding the report counts needs its disposition before the comment can go out.
      def check_count!
        counted = @report.match(CLOSING)[2].to_i
        return if @findings.size == counted

        raise Error, "Round #{@number}'s report counts #{counted} findings; #{@findings.size} were recorded."
      end

      def outcome
        return '' if @findings.empty?

        fixed = @findings.count(&:fixed?)
        " (#{fixed} fixed, #{@findings.size - fixed} documented)"
      end

      # A subscription session has no per-token bill; its API-equivalent estimate is marked as one.
      def cost
        estimate = value('estimate')
        value('cost') || (estimate ? "#{estimate} est." : 'UNKNOWN')
      end

      def dispositions(links, fixed_before)
        return '' if @findings.empty?

        lines = @findings.map do |finding|
          result = finding.fixed? ? "fixed in #{links.commit(finding.commit)}" : finding.label
          line = "- `#{finding.id}` #{finding.kind}: #{finding.summary} — #{result}"
          line += " — #{finding.note}" if finding.note
          returned = fixed_before[finding.id]
          returned ? "#{line} · **returned after its fix in #{links.commit(returned)}**" : line
        end
        "**Dispositions**\n\n#{lines.join("\n")}\n\n"
      end

      def prompt(links)
        source = optional('prompt_source', 'Shaka default')
        ref = @spec['criteria_ref']
        return "#{source} · criteria not supplied" if ref.nil?
        raise Error, "Round #{@number} criteria_ref must be a full commit SHA." unless
          ref.to_s.match?(LocalReviewEvidence::SHA)

        "#{source} · criteria #{links.criteria(ref)}"
      end

      def field(name) = PublicationText.single_line(@spec[name], "round #{@number} #{name}").strip

      def optional(name, default = 'UNKNOWN')
        value = @spec[name]
        value.nil? || (value.is_a?(String) && value.strip.empty?) ? default : field(name)
      end

      def read_report
        path = field('report')
        text = File.read(path, encoding: 'UTF-8')
        raise Error, "Round #{@number} report is not UTF-8." unless text.valid_encoding?
        unless LocalReviewEvidence.valid?(text, head: @head, reviewer: @reviewer)
          raise Error, "Round #{@number} report does not close with REVIEWED #{@head} BY #{@reviewer}."
        end

        text
      end
    end
  end
end
