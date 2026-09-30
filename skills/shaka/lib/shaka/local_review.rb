# frozen_string_literal: true

require 'json'
require 'optparse'
require_relative 'error'
require_relative 'github'
require_relative 'local_review/comment'
require_relative 'local_review/ledger'
require_relative 'local_review/runner'
require_relative 'local_review/report_check'
require_relative 'evidence/review'

module Shaka
  # Entry point for process-verified reviews and explicitly weaker host reports.
  class LocalReview
    def self.run(arguments, github: nil)
      new(arguments, github:).run
    rescue OptionParser::ParseError, SystemCallError, JSON::ParserError, Shaka::Error => e
      warn "shaka: #{e.message}"
      1
    end

    def initialize(arguments, github: nil)
      @arguments = arguments.dup
      @options = {}
      @github = github
    end

    ACTIONS = %w[run check record publish].freeze

    def run
      action = @arguments.shift
      raise OptionParser::InvalidArgument, "Usage: shaka review (#{ACTIONS.join('|')}) [options]" unless
        ACTIONS.include?(action)

      parser = send(:"#{action}_parser")
      parser.parse!(@arguments)
      return 0.tap { puts parser } if @options[:help]
      return send(action, parser) if %w[record publish].include?(action)

      raise OptionParser::InvalidArgument, parser.to_s unless @arguments.empty?

      present(dispatch(action))
    end

    private

    def present(result)
      puts JSON.pretty_generate(result)
      %w[completed reported].include?(result.fetch('status')) ? 0 : 1
    end

    def run_parser
      OptionParser.new do |flags|
        flags.banner = 'Usage: shaka review run --root DIR --base SHA --head SHA --reviewer ID'
        %w[root base head reviewer effort model criteria-ref settings-ref repository description-file timeout-seconds
           ledger].each do |key|
          flags.on("--#{key} VALUE") { |value| @options[key.tr('-', '_').to_sym] = value }
        end
        flags.on('-h', '--help') { @options[:help] = true }
      end
    end

    def dispatch(action)
      original_path = ENV.fetch('PATH', nil)
      evidence = Evidence::Review.start(@options, action:)
      result = action == 'run' ? LocalReviewRunner.new(@options).run : LocalReviewReportCheck.new(@options).run
      evidence ? evidence.finish(result) : result
    ensure
      ENV['PATH'] = original_path
    end

    # `merge` decides whether the attested commit covers the PR head, so publishing does not.
    def publish(parser)
      raise OptionParser::InvalidArgument, parser.to_s unless @arguments.length == 2 && @options[:content_file]

      github = @github || GitHub.new(*@arguments)
      comment = review_comment(github)
      body = comment.render
      comment.check_rendering!(github.markdown(body))
      puts JSON.pretty_generate(github.reply(body:, key: LocalReviewComment::KEY))
      0
    end

    def record(parser)
      raise OptionParser::InvalidArgument, parser.to_s unless
        @arguments.empty? && @options[:ledger] && @options[:content_file]

      ledger = LocalReviewLedger.new(@options[:ledger])
      number = ledger.record!(JSON.parse(File.read(@options[:content_file], encoding: 'UTF-8')))
      puts JSON.pretty_generate('ledger' => ledger.path, 'round' => number)
      0
    end

    def record_parser
      OptionParser.new do |flags|
        flags.banner = 'Usage: shaka review record --ledger PATH --content-file PATH'
        flags.on('--ledger PATH') { |value| @options[:ledger] = value }
        flags.on('--content-file PATH') { |value| @options[:content_file] = value }
        flags.on('-h', '--help') { @options[:help] = true }
      end
    end

    def review_comment(github)
      content = JSON.parse(File.read(@options[:content_file], encoding: 'UTF-8'))
      LocalReviewComment.new(content, repository: @arguments.first, published: on_github(github))
    end

    # The Git data API answers 404 for a commit GitHub does not have, such as one a rebase replaced.
    # Any other failure stops publication, so a passing outage cannot mislabel a pushed commit.
    def on_github(github)
      lambda do |sha|
        github.api("repos/#{@arguments.first}/git/commits/#{sha}")
        true
      rescue Shaka::Error => e
        raise unless e.http_status == 404

        false
      end
    end

    def publish_parser
      OptionParser.new do |flags|
        flags.banner = 'Usage: shaka review publish OWNER/REPO NUMBER --content-file PATH'
        flags.on('--content-file PATH') { |value| @options[:content_file] = value }
        flags.on('-h', '--help') { @options[:help] = true }
      end
    end

    def check_parser
      OptionParser.new do |flags|
        flags.banner = 'Usage: shaka review check --head SHA (--reviewer ID --report PATH | --not-run-reason TEXT)'
        %w[head reviewer report not-run-reason root settings-ref repository].each do |key|
          flags.on("--#{key} VALUE") { |value| @options[key.tr('-', '_').to_sym] = value }
        end
        flags.on('-h', '--help') { @options[:help] = true }
      end
    end
  end
end
