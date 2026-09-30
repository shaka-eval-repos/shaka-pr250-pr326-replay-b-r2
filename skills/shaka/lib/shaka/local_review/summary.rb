# frozen_string_literal: true

module Shaka
  # Links a commit to GitHub only when GitHub has it. A round reviewed before a rebase names a
  # commit that was never pushed, and a link to it would open a 404 page.
  class LocalReviewLinks
    def initialize(repository, published = nil)
      @repository = repository
      @published = published
      @known = {}
    end

    # Code spans are never auto-linked, so a commit needs an explicit link to be clickable.
    def commit(sha)
      code = "`#{sha[0, 7]}`"
      return code unless @repository
      return "#{code} (not on GitHub)" unless on_github?(sha)

      "[#{code}](https://github.com/#{@repository}/commit/#{sha})"
    end

    def criteria(sha)
      code = "`#{sha[0, 7]}`"
      # The criteria can come from nested AGENTS.md files alone, so the link opens the commit's tree.
      @repository ? "[#{code}](https://github.com/#{@repository}/tree/#{sha})" : code
    end

    private

    def on_github?(sha)
      return true unless @published

      @known.fetch(sha) { @known[sha] = @published.call(sha) }
    end
  end

  # The lines under the summary table: what the loop cost, why it stopped, and what the prompt
  # column means.
  class LocalReviewSummary
    INSTRUCTIONS = 'https://github.com/shakacode/shaka/blob/main/skills/shaka/config/review-prompt.md'
    RULES = 'https://github.com/shakacode/shaka/blob/main/skills/shaka/lib/shaka/review_prompt.rb'
    NUMBER = /\A\d{1,3}(?:,\d{3})*\z|\A\d+\z/
    # `shaka usage` marks an estimate that leaves some responses unpriced as `(partial)`.
    MONEY = /\A\$?(\d+(?:\.\d+)?)( \(partial\))?\z/

    def initialize(rounds) = @rounds = rounds

    def lines = [total, outcome, prompt]

    private

    def total
      "**Total:** #{@rounds.size} #{@rounds.size == 1 ? 'round' : 'rounds'} · #{tokens} · #{cost}"
    end

    def tokens
      counts = @rounds.map { |round| round.value('tokens').to_s }
      return 'tokens UNKNOWN' unless counts.all? { |count| count.match?(NUMBER) }

      "#{group(counts.sum { |count| count.delete(',').to_i })} tokens"
    end

    # A subscription session has no per-token bill, so its dollar figure is an API-equivalent estimate.
    def cost
      prices = @rounds.map { |round| price(round).match(MONEY) }
      return 'cost UNKNOWN' if prices.any?(&:nil?)

      format('$%<sum>.2f %<label>s', sum: prices.sum { |match| match[1].to_f }, label: cost_label(prices))
    end

    def cost_label(prices)
      label = @rounds.all? { |round| round.value('cost') } ? 'cost' : 'API-equivalent estimate'
      prices.any? { |match| match[2] } ? "#{label} (partial)" : label
    end

    def price(round) = (round.value('cost') || round.value('estimate')).to_s

    # A finding ever classed a defect stays open until a later round records its fix, so neither a
    # clean last round nor a later reclassification hides it.
    def outcome
      open = unfixed_defects
      return "**Outcome:** the loop stopped with #{defects(open)} left for the maintainer." if open.positive?

      batch = @rounds.select { |round| round.head == @rounds.last.head }
      findings = batch.flat_map(&:findings)
      label = batch.size == 1 ? "round #{@rounds.size}" : 'the final batch'
      return "**Outcome:** the loop ended clean: #{label} found nothing." if findings.empty?

      "**Outcome:** the loop ended with nothing left to fix. #{label.capitalize}'s findings are documented " \
        "nits or risks (#{kinds(findings)})."
    end

    def unfixed_defects
      latest = {}
      defects = []
      @rounds.each do |round|
        round.findings.each do |finding|
          key = [round.reviewer, finding.id]
          defects << key if finding.kind == 'defect'
          latest[key] = finding
        end
      end
      defects.uniq.count { |id| !latest.fetch(id).fixed? }
    end

    def defects(count) = "#{count} unfixed #{count == 1 ? 'defect' : 'defects'}"

    def kinds(findings)
      LocalReviewFinding::CLASSES.filter_map do |kind|
        count = findings.count { |finding| finding.kind == kind }
        "#{count} #{kind}" if count.positive?
      end.join(', ')
    end

    def prompt
      "**Prompt:** `Shaka default` is Shaka's [review instructions](#{INSTRUCTIONS}) plus its " \
        "[fixed rules](#{RULES}); a `review.prompt_file` entry names the repository file used instead. " \
        '`criteria SHA` means the reviewer also received the trusted `AGENTS.md` files from that commit.'
    end

    def group(number) = number.to_s.reverse.scan(/\d{1,3}/).join(',').reverse
  end
end
