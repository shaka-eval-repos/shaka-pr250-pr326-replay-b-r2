# frozen_string_literal: true

require_relative 'test_helper'
require_relative 'repository_fixture'
require 'shaka/configuration'

class ConfigurationBoundaryTest < Minitest::Test
  include RepositoryConfigTestHelpers

  ROOT = File.expand_path('../skills/shaka/lib/shaka', __dir__)
  INTERNAL = %w[configuration.rb repository_config.rb trusted_config_source.rb].freeze
  OTHER_PATHS = %w[merge_review_comparison.rb seam/initializer_readme.rb seam/pointer.rb].freeze
  OTHER_GIT_READ = %w[local_review/criteria.rb seam/upgrade_plan/indexed_references.rb].freeze
  OTHER_FILE_IO = %w[
    checkpoint.rb doctor.rb doctor/installation_identity.rb doctor/cursor_stop_hook.rb local_review/ledger_storage.rb
    enforcement_config.rb evidence/command.rb evidence/verification.rb installer.rb install/source.rb install/tree.rb
    install/link_lock.rb install/package.rb install/package_verification.rb install/version.rb local_review/ledger.rb
    local_review.rb local_review/cli.rb local_review/comment.rb local_review/path_guard.rb local_review/shebang.rb
    local_review/report_check.rb local_review/runner.rb merge_tree_proof.rb opening_parse.rb opening_check.rb
    opening_verdict_cache.rb recommendation.rb repos/home.rb review_prompt.rb usage/claude_usage.rb usage/codex_usage.rb
    usage/cursor_usage_store.rb usage/opencode_usage.rb usage/pi_usage.rb usage/rate_card.rb pr_watch/command.rb
    workflow_config.rb seam/upgrade_plan.rb seam/upgrade_plan/inventory.rb seam/upgrade_plan/references.rb
    seam/upgrade_plan/reference_patterns.rb seam/private_recovery.rb seam/private_recovery/copies.rb
    seam/private_recovery/preparation.rb seam/private_recovery/rotation.rb seam/private_recovery/identity.rb
    seam/upgrade_plan/reference_dependencies.rb seam/upgrade_plan/continued_references.rb seam/upgrader/recovery.rb
    seam/upgrade_plan/symlink_chain.rb seam/private_recovery/exclusion.rb seam/upgrader.rb seam/upgrader/filesystem.rb
  ].freeze

  def test_public_paths_remain_concrete_and_independent
    paths = Shaka::Configuration::Paths
    assert_equal '.agents/agent-workflow.yml', paths::CONTRACT
    assert_equal '.agents', paths::DIRECTORY
    assert_equal '.agents/bin', paths::COMMAND_DIRECTORY
    assert_equal '.agents/shaka.md', paths::POINTER
    assert_equal '~/.agents/trusted-github-actors.yml', paths::MACHINE_ALLOWLIST
    assert_equal '.agents/trusted-github-actors.yml', paths::REPOSITORY_ALLOWLIST
    assert_equal '.agents/bin/validate', paths::REQUIRED_COMMANDS.fetch('validate')
    assert_equal '.agents/bin/validate-local', paths::OPTIONAL_COMMANDS.fetch('validate_local')
    assert_equal '.agents/bin/trigger-hosted-ci', paths::OPTIONAL_COMMANDS.fetch('trigger_hosted_ci')
  end

  def test_repository_path_lookup_rejects_machine_and_command_collections
    assert_equal '/repo/.agents/agent-workflow.yml', Shaka::Configuration.path('/repo', :CONTRACT)
    assert_raises(KeyError) { Shaka::Configuration.path('/repo', :MACHINE_ALLOWLIST) }
    assert_raises(KeyError) { Shaka::Configuration.path('/repo', :COMMANDS) }
  end

  def test_generated_file_reader_rejects_arbitrary_paths
    error = assert_raises(Shaka::Error) do
      Shaka::Configuration.generated_text(root: '/repo', path: '/repo/other.yml')
    end

    assert_includes error.message, 'Not a generated configuration path'
  end

  def test_trusted_read_never_uses_a_valid_worktree_as_fallback
    with_repository do |root|
      File.write(File.join(root, 'README.md'), "Fixture\n")
      commit_fixture(root, 'README.md')

      assert_instance_of Shaka::RepositoryConfig, Shaka::Configuration.worktree(root:)

      error = assert_raises(Shaka::Error) { Shaka::Configuration.trusted(root:, ref: 'HEAD') }

      assert_includes error.message, 'Cannot read .agents/agent-workflow.yml'
    end
  end

  def test_invalid_trusted_contract_does_not_use_valid_worktree
    with_repository do |root|
      contract = File.join(root, '.agents/agent-workflow.yml')
      valid = File.read(contract)
      File.write(contract, "review: [invalid\n")
      commit_fixture(root, '.')
      File.write(contract, valid)

      assert_instance_of Shaka::RepositoryConfig, Shaka::Configuration.worktree(root:)
      error = assert_raises(Shaka::Error) { Shaka::Configuration.trusted(root:, ref: 'HEAD') }
      assert_includes error.message, 'Invalid .agents/agent-workflow.yml'
    end
  end

  def test_production_config_access_has_one_owner
    violations = Dir.glob(File.join(ROOT, '**/*.rb')).filter_map { |file| boundary_violation(file) }

    assert_empty violations, violations.join("\n")
  end

  private

  def commit_fixture(root, path)
    system('git', '-C', root, 'init', '--quiet', exception: true)
    system('git', '-C', root, 'add', path, exception: true)
    system('git', '-C', root, '-c', 'user.name=Test', '-c', 'user.email=test@example.com',
           'commit', '--quiet', '-m', 'Trusted fixture', exception: true)
  end

  def boundary_violation(file)
    relative = file.delete_prefix("#{ROOT}/")
    return if INTERNAL.include?(relative) || relative.start_with?('configuration/', 'repository_config/')

    findings = source_findings(relative, File.read(file))
    "#{relative}: #{findings.join(', ')}" unless findings.empty?
  end

  def source_findings(relative, source)
    path_findings(relative, source) + access_findings(relative, source)
  end

  def path_findings(relative, source)
    findings = []
    literal = source.include?('.agents')
    findings << 'path literal' if literal && !OTHER_PATHS.include?(relative)
    findings << 'contract alias' if source.include?('RepositoryConfig::PATH')
    findings
  end

  def access_findings(relative, source)
    findings = []
    direct_read = /File\.(?:read|binread|write)\([^\n]*(?:CONTRACT|SEAM|POINTER_PATH)/
    findings << 'direct contract read' if source.match?(direct_read)
    direct_access = source.match?(/File\.(?:read|binread|write|open)\(/)
    findings << 'unclassified file access' if direct_access && !OTHER_FILE_IO.include?(relative)
    git_read = source.match?(/['"](?:show|cat-file)['"]/) && !OTHER_GIT_READ.include?(relative)
    findings << 'unclassified Git read' if git_read && relative != 'trusted_path_resolver.rb'
    findings
  end
end
