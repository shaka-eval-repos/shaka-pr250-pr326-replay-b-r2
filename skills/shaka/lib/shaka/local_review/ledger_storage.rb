# frozen_string_literal: true

module Shaka
  # Atomic ledger persistence and optimistic checks around short exclusive writes.
  module LocalReviewLedgerStorage
    private

    def data
      @data ||= if File.exist?(@path)
                  parsed = JSON.parse(File.read(@path, encoding: 'UTF-8'))
                  raise Error, "#{@path} is not a review ledger." unless
                    parsed.is_a?(Hash) && parsed['rounds'].is_a?(Array)

                  parsed
                else
                  { 'rounds' => [] }
                end
    end

    # A reviewer may finish after peers append to its head, but not after history was replaced
    # or advanced. Check its observed prefix before merging the fresh file under the lock.
    def check_snapshot!(snapshot, head)
      old = snapshot.fetch('rounds')
      stable = old.each_with_index.all? { |round, index| same_evidence?(round, rounds[index], head) } &&
               rounds.drop(old.size).all? { |round| round['head'] == head }
      raise Error, 'The review ledger changed while the reviewer ran; result is stale.' unless stable
    end

    def same_evidence?(old, current, head)
      return old == current unless old['head'] == head && current

      mutable = %w[findings model tokens cost estimate]
      old.except(*mutable) == current.except(*mutable)
    end

    # Lock a stable sidecar, not the ledger inode replaced by atomic rename. Never unlink the
    # lock: another process may already be waiting on that inode.
    def transaction
      File.open("#{@path}.lock", File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        @data = nil
        yield
      ensure
        lock.flock(File::LOCK_UN)
      end
    end

    def write(content)
      temporary = "#{@path}.#{Process.pid}.tmp"
      File.write(temporary, "#{JSON.pretty_generate(content)}\n", perm: 0o600)
      File.rename(temporary, @path)
      @data = content
    ensure
      File.unlink(temporary) if temporary && File.exist?(temporary)
    end
  end
end
