# frozen_string_literal: true

require 'yaml'
require_relative 'error'
require_relative 'merge_limits'
require_relative 'prose_limits'
require_relative 'configuration/paths'
require_relative 'configuration/layout'
require_relative 'repository_config/duplicate_keys'
require_relative 'repository_config/schema'

module Shaka
  # Loads the small, typed repository contract used by the workflow.
  class RepositoryConfig
    DEFAULT_WIP = { 'include_locations' => true }.freeze

    # base_branch is nil when the seam omits it, meaning the repository's default branch.
    attr_reader :base_branch, :commands, :review, :merge, :wip, :opening_check, :prose_limits, :sha, :config_path

    def self.load(root: Dir.pwd, source: nil, available_commands: nil, sha: nil, candidate_commands: true)
      new(root:, source:, available_commands:, sha:, candidate_commands:).load
    end

    def self.prompt_files(review:, opening:)
      files = ReviewSchema.prompt_files(review)
      path = opening['prompt_file']
      path ? files + [['opening_check.prompt_file', path]] : files
    end

    def initialize(root:, source: nil, available_commands: nil, sha: nil, candidate_commands: true)
      if source && available_commands.nil?
        raise Error, 'available_commands is required when repository policy comes from another source'
      end

      @root = File.realpath(root)
      @source = source
      @available_commands = available_commands
      @sha = sha
      @candidate_commands = candidate_commands
      select_paths
    end

    def select_paths
      @layout = sha ? Configuration::Layout.commit(root: @root, sha:) : Configuration::Layout.worktree(root: @root)
      @candidate_detected = if @candidate_commands
                              sha ? Configuration::Layout.worktree(root: @root, allow_missing: true) : @layout
                            end
      @candidate_layout = @candidate_detected || @layout
      @selection = Configuration::Layout::Selection.new(policy: @layout, candidate: @candidate_layout)
      @config_path = @layout.contract
    end

    private :select_paths

    def load
      source = @source || File.read(File.join(@root, config_path), encoding: 'UTF-8')
      DuplicateKeys.check(source, filename: config_path)
      @data = YAML.safe_load(source, permitted_classes: [], permitted_symbols: [], aliases: false)
      apply_schema
      self
    rescue Psych::Exception => e
      raise Error, "Invalid #{config_path}: #{e.message}"
    end

    def command(name)
      commands.fetch(name.to_s)
    end

    # Callers read this as the effective contract, so defaults belong in it.
    def to_h
      @data.merge('commands' => commands, 'review' => review, 'merge' => merge, 'wip' => wip,
                  'paths' => { 'policy_configuration' => config_path,
                               'candidate_configuration' => @candidate_detected&.contract,
                               'trusted_command_directory' => @layout.command_directory,
                               'candidate_command_directory' => @candidate_layout.command_directory },
                  'opening_check' => opening_check, 'prose_limits' => prose_limits)
    end

    private

    def apply_schema
      schema = Schema.new(root: @root, data: @data, available_commands: @available_commands,
                          candidate_commands: @candidate_commands, selection: @selection)
      schema.validate
      @commands = schema.commands
      assign_sections
    end

    def assign_sections
      @base_branch = @data['base_branch']
      @review = with_default_review_wait(@data.fetch('review'))
      merge = @data.fetch('merge')
      @merge = merge.merge('limits' => MergeLimits.new(merge.fetch('limits', {})).to_h)
      @wip = DEFAULT_WIP.merge(@data.fetch('wip', {}))
      @opening_check = { 'external_enabled' => true }.merge(@data.fetch('opening_check', {}))
      @prose_limits = ProseLimits.new(@data.fetch('prose_limits', {})).to_h
    end

    def with_default_review_wait(review)
      { 'ci_review_wait' => 'one', 'local_review_count' => 1 }.merge(review)
    end
  end
end
