# frozen_string_literal: true

require_relative 'local_review_test'
require 'shaka/local_review/ledger'

module LocalReviewBatchFixture
  include LocalReviewFixture

  COMMAND = LocalReviewCodexTest::COMMAND
  BATCH_SCRIPT = <<~'SCRIPT'
    #!/usr/bin/env ruby
    require 'json'
    prompt = STDIN.read
    File.write(ENV.fetch('BATCH_TRACE'), prompt)
    if ENV['BATCH_READY']
      File.write(ENV.fetch('BATCH_READY'), '')
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
      until File.exist?(ENV.fetch('BATCH_RELEASE'))
        abort 'barrier timed out' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        sleep 0.01
      end
    end
    codex = File.basename($PROGRAM_NAME) == 'codex'
    id = codex ? 'openai/codex' : 'anthropic/claude'
    effort = codex ? 'UNKNOWN' : 'medium'
    text = "peer-current-secret\nREVIEWED #{ENV.fetch('BATCH_HEAD')} BY #{id} EFFORT #{effort} FINDINGS #{ENV.fetch('BATCH_COUNT', '1')}\n"
    if codex
      File.write(ARGV.fetch(ARGV.index('-o') + 1), text)
    else
      puts JSON.generate(is_error: false, result: text)
    end
  SCRIPT

  def teardown
    Array(@results).each { |result| cleanup_artifacts(result) }
    super
  end

  private

  def with_batch
    Dir.mktmpdir('review-batch') do |directory|
      with_repository do |root, base, head, bin|
        batch_paths(root, base, head, bin, directory)
        %w[codex claude].each { |name| batch_cli(name) }
        yield
      end
    end
  end

  def batch_paths(root, base, head, bin, directory)
    @root = root
    @base = base
    @head = head
    @bin = bin
    @directory = directory
    @ledger = File.join(directory, 'ledger.json')
  end

  def batch_cli(name) = write_executable(@bin, name, BATCH_SCRIPT)

  def review(id, label: id.split('/').first, barrier: false, count: 1)
    environment = { 'BATCH_HEAD' => @head, 'BATCH_COUNT' => count.to_s,
                    'BATCH_TRACE' => File.join(@directory, "#{label}.prompt") }
    if barrier
      environment['BATCH_READY'] = File.join(@directory, "#{label}.ready")
      environment['BATCH_RELEASE'] = File.join(@directory, 'release')
    end
    output, error, status = run_review(@root, @base, @head, @bin, reviewer: id, ledger: @ledger, env: environment)
    result = JSON.parse(output)
    (@results ||= []) << result
    [result, status, error]
  end

  def successful_review(id, **)
    result, status, error = review(id, **)
    assert_predicate status, :success?, "#{result}\n#{error}"
    result
  end

  def record_round(number, summary: 'earlier finding', **changes)
    content = { 'round' => number, 'head' => @head,
                'findings' => [{ 'id' => 'F1', 'summary' => summary, 'class' => 'risk',
                                 'disposition' => 'documented',
                                 'note' => 'private disposition note' }.merge(changes.transform_keys(&:to_s))] }
    path = File.join(@directory, "record-#{number}.json")
    File.write(path, JSON.generate(content))
    output, error, status = Open3.capture3(COMMAND, 'review', 'record', '--ledger', @ledger, '--content-file', path)
    assert_predicate status, :success?, "#{output}\n#{error}"
    assert_equal number, JSON.parse(output).fetch('round')
  end

  def assert_review_refused(message, id: 'openai/codex')
    result, status, = review(id)
    refute_predicate status, :success?
    assert_includes result.fetch('reason'), message
  end

  def assert_isolated_prompt
    prompt = File.read(File.join(@directory, 'anthropic.prompt'))
    assert_includes prompt, 'earlier finding'
    refute_includes prompt, 'current finding'
    refute_includes prompt, 'peer-current-secret'
    refute_includes prompt, 'private disposition note'
  end

  def next_head
    commit!(@root, "change #{@head}", 'Next batch')
    @head = git!(@root, 'rev-parse', 'HEAD').strip
  end

  def ledger = JSON.parse(File.read(@ledger))

  def wait_ready(*labels)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until labels.all? { |label| File.exist?(File.join(@directory, "#{label}.ready")) }
      raise 'fake reviewer did not reach barrier' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.01
    end
  end

  def release = File.write(File.join(@directory, 'release'), '')
end
