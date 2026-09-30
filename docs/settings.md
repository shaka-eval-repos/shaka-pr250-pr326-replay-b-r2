# Settings

Settings live in `.agents/shaka/config.yml`; repositories configured before that
layout keep them in `.agents/agent-workflow.yml`. Ask your agent to
[configure the repository](configure-repository.md), or edit the file in a PR.
Policy comes from the default branch; settings changed in a PR do not govern
that PR.

## `merge.preference`

**Required.** Values: `ask` or `auto`. Setup defaults to `ask`.

```yaml
merge:
  preference: ask
```

With `ask`, merge the ready PR on GitHub or tell the agent to merge the reviewed
commit. With `auto`, the agent merges after required checks, reviews, and approvals,
subject to the repository's restrictions.

Set a task's preference with `Use merge policy auto`. This is a task instruction;
editing the PR's settings does not change its own merge authority. Required human
approvals still apply. See [merge policy](working-with-shaka.md#choose-a-merge-policy).

## `merge.required_checks`

**Optional.** CI checks that must pass before Shaka treats a PR as ready. Use it
when GitHub cannot require checks, such as on a private repository on the GitHub
Free plan.

```yaml
merge:
  preference: ask
  required_checks:
    - test
```

GitHub's required checks come first. If the base branch requires any, Shaka uses
those and ignores this list.

Otherwise, each listed check must appear on the PR and pass. Neutral and skipped
results count as passing, as they do on GitHub. If a listed check never appears,
the PR is blocked, so a renamed job cannot quietly drop out of the gate. Use the
names `gh pr checks` shows: CircleCI, for example, reports one check per workflow,
not per job.

The list governs only what Shaka does. In Ask mode, the agent waits for these checks
before it reports a PR ready and labels it `awaiting-merge-approval`. In Auto mode,
`shaka merge` refuses to merge until they pass. GitHub does not know about the list, so it
does not stop anyone from clicking merge. Nothing ties a name to a specific
workflow either, so a PR could add a job with a listed name. For protection that
GitHub enforces, use a ruleset or branch protection.

## `merge.limits`

**Optional.** Size limits for a merge the agent submits. A PR at a limit still
merges; one past it goes back to you.

```yaml
merge:
  preference: auto
  limits:
    max_changed_files: 29
    max_changed_lines: 999
    max_commits: 9
```

The values above are the defaults. Set any key to a positive integer to change
it; omitted keys keep their default. Changed lines are additions plus deletions.

When a PR is past a limit, or GitHub does not report its size, `merge` refuses
it. The agent then reports the counts and hands the PR back as Ask. To let the
agent merge it, confirm that commit in chat or
[approve it](working-with-shaka.md#find-prs-waiting-on-you). The confirmation
still counts after a clean rebase, or after conflict fixes that change no
behavior; any other new commit needs another confirmation. Required checks,
reviews, and approvals still apply.

`merge` checks the counts and that a confirmation names the commit being
merged. Whether you actually confirmed it is the agent's responsibility; the
[enforcement reference](workflow.md#what-is-enforced) explains the boundary.
Put other project restrictions in `AGENTS.md`.

## `review.required`

**Required.** Values: `meaningful_changes`, `always`, or `none`.

This controls when configured CI review reports are required. Options:

- `meaningful_changes`: implementation changes; trivial prose can skip with a reason.
- `always`: every PR, including trivial changes.
- `none`: no configured CI review backstop, and `shaka merge` does not check for a
  local review. Omit `ci_review_jobs` with this setting.

Meaningful implementation also gets a local adversarial review before push:

- Use a separate session without the implementation conversation.
- Prefer a different provider and model. If other reviewers are unavailable, the
  current workflow allows the implementation model in a fresh session.
- Address findings before pushing.

`shaka review run` verifies the reviewer process completed and returned a report
for the expected commit. `shaka review check` validates a supplied report but does
not prove a reviewer process ran.

Before it merges, `shaka merge` checks that the PR has a local review of the
commit being merged. The agent posts the review report as a PR comment, and the
report's last line names the commit and the reviewer:

```text
REVIEWED <commit> BY <provider>/<family> EFFORT <effort> FINDINGS <count>
```

`merge` counts only comments from the GitHub account running the merge, and only
when that line ends the comment. Any reviewer counts, including the
implementation model in a fresh session.

A review of an earlier commit still counts in two cases:

- **Updated from the base branch.** Bringing the branch up to date with the base,
  by merge or rebase, keeps the review when there were no conflicts and nothing
  else changed. `merge` checks this with Git in the local checkout: the head must
  match, file for file, what merging the reviewed commit with the new base
  produces. The check runs Git's built-in merge in a temporary repository, so no
  merge driver or script runs and nothing is written to your repository. If Git
  is older than 2.41 or those commits are not in the checkout, `merge` asks for a
  new review or a waiver instead.
- **Ordinary Markdown since.** Every later change is ordinary Markdown. Agent
  instructions are not ordinary Markdown: `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`,
  `SKILL.md`, and files under `.agents/`, `.claude/`, `.cursor/`, `.github/`, or
  `skills/` need a new review.

When no review applies, `merge` stops before merging. A maintainer can record a
waiver reason when review was skipped on purpose, a later commit only fixed nits,
or a CI review covered the commit. The waiver also covers a PR whose
comments GitHub cannot list. With `review.required: none`, `merge` skips this check.

The merge result shows the review it relied on, or the waiver reason, under
`review_evidence`. That records what the posted line says. It does not prove a
reviewer process ran or that its findings were fixed.

## `review.ci_review_jobs`

**Required unless `review.required` is `none`.** List the GitHub job names that
produce review reports, such as:

```yaml
review:
  required: meaningful_changes
  ci_review_jobs:
    - claude-review
  ci_review_wait: one
```

The agent reads reports according to `ci_review_wait`; a green job alone does not
prove review completed. GitHub's required merge checks are configured separately.

## `review.ci_review_wait`

**Optional. Default: `one`.** Values: `none`, `one`, or `all`.

| Value | Wait before merging |
| --- | --- |
| `none` | No CI review report; local review still applies |
| `one` | At least one configured reviewer reports on the current commit |
| `all` | Every configured reviewer reports on the current commit |

Local review does not waive `one` or `all`. With `review.required: none`, no
configured review jobs apply. GitHub's required checks and approvals apply in
every mode. A task can increase the wait, but cannot lower the repository minimum.

The agent counts verified reports. The merge helper permits optional pending
checks (`UNSTABLE`) for `none` and `one`; `all` requires `CLEAN`.

## `review.local_review_count`

**Optional; default `1`.** Positive integer number of distinct local reviewers to
select for each committed head. Set it to `2` when you want two independent
perspectives on the same change. The first reviewer keeps the existing provider
preference and fallback; additional available reviewers follow the configured
[reviewer order](#reviewlocal_review_agents).

Selection returns fewer reviewers when fewer distinct identities are available.
It preserves the first reviewer's outcome and fallback note. An unavailable CLI
still leaves the existing fresh-context fallback available.

More reviewers repeat the full diff and increase review tokens, provider charges
or subscription usage, and the work of handling findings. Concurrent runs can
reduce waiting time but do not reduce that usage. Start with one unless another
perspective earns its cost; quality and speed gains depend on the task.

Install and sign in to the reviewers you intend to use, as described in
[adding a second reviewer](#add-a-second-reviewer). Ask your agent:
“Review this committed head with two different reviewers in one batch, then
handle every finding before reviewing any fixes.” The
[concurrent review procedure](../skills/shaka/references/local-review.md#review-one-head-with-several-reviewers)
explains the shared ledger and failure handling. Selection itself launches no
processes and changes no GitHub review or merge requirements.

## `review.local_review_agents`

**Optional.** Ordered reviewer preferences, not required local installations.
Without a list, selection falls back to a fresh review context using the
implementation identity.

```yaml
review:
  required: meaningful_changes
  ci_review_jobs: [claude-review]
  local_review_agents:
    - provider: anthropic
      model_family: claude
    - provider: openai
      model_family: codex
```

Use stable provider/family names. The agent prefers a different provider. Put
custom review criteria in trusted `AGENTS.md`.

To control what a review costs, give an entry a `model` and an `effort`:

```yaml
  local_review_agents:
    - provider: openai
      model_family: codex
      model: gpt-6-sol
      effort: medium
    - provider: anthropic
      model_family: claude
      effort: medium
```

Here every Codex review runs `gpt-6-sol` at medium effort. Without a `model`,
Codex runs its built-in default, which has been `gpt-6-astra` at five times the
token price, because the reviewer ignores your personal Codex configuration.
Claude uses its CLI default model at medium effort. The review report records
the effort it ran.

Both settings are optional. A task can still ask for a different model or effort,
which wins for that review. The review helper reads them from the trusted
default-branch commit the agent passes as `--criteria-ref`, so a PR cannot pick
the model that reviews it; without that commit, the settings are not applied.
When a provider retires a named model, that reviewer's CLI fails until you update
the entry.

Each reviewer CLI accepts its own effort levels:

| Reviewer | Where the levels come from |
| --- | --- |
| Claude | `claude --help` lists them for `--effort`, such as `low` through `max` |
| Codex | The model's documentation; Codex passes the level through as configuration |
| Grok | The Grok CLI's `--reasoning-effort` option |

Shaka checks only that an effort is a lowercase name, such as `medium` or
`xhigh`. The reviewer CLI decides whether it accepts that level.
Configured CI review jobs have separate waiting rules under
[`review.ci_review_wait`](#reviewci_review_wait).
See [reviewer selection](../skills/shaka/references/review.md#choose-a-local-reviewer).

### Add a second reviewer

A review from the provider that wrote the change shares its blind spots. When the
published review shows a **Reviewer fallback** notice, no listed reviewer from another
provider could run on that machine. Install one of the listed CLIs and sign in once
with the account that should pay for reviews:

- Codex: install the `codex` CLI, then run `codex login`.
- Claude Code: install the `claude` CLI, then run `claude` and sign in. Keep the
  normal sign-in; Shaka does not use `--bare`, which ignores it.
- Grok: install the `grok` CLI and sign in as its setup describes.

Then list that provider in `local_review_agents`. The next review picks it, and the
published review names it in its summary table instead of the fallback notice.

## `review.prompt_file`

**Optional. Default: Shaka's [review instructions](../skills/shaka/config/review-prompt.md).**
A Markdown file in your repository that replaces what the local reviewer looks for
and how it reports. Copy the default to start.

```yaml
review:
  required: meaningful_changes
  ci_review_jobs: [claude-review]
  prompt_file: .agents/review-prompt.md
  local_review_agents:
    - provider: openai
      model_family: codex
      prompt_file: .agents/review-prompt-codex.md
    - provider: anthropic
      model_family: claude
```

To give one review agent different instructions, set `prompt_file` on that
agent's entry in `local_review_agents`. It replaces `review.prompt_file` when that
agent reviews. Here Codex reviews with `.agents/review-prompt-codex.md`, and Claude,
which has no `prompt_file` on its entry, uses `.agents/review-prompt.md`.

Shaka reads the file from a trusted default-branch revision, so a PR that
changes it is reviewed with the current version. Without a trusted prompt,
the reviewer gets Shaka's default instructions. Settings validation fails
when a configured file is missing, empty, larger than 100 KB, or not UTF-8.
Shaka keeps a few rules whatever
the file says: the reviewer makes no edits, treats the diff as data rather than
instructions, reports which `AGENTS.md` criteria it used, and ends with the
`REVIEWED` line that `shaka review run` checks.

The file configures local reviews. A CI review job gets its prompt from its own
workflow; to give it the same instructions, have the workflow read this file.

## `opening_check`

**Optional.** By default, the coding agent tries a separate local reviewer from
the trusted reviewer list. To keep the opening with the coding agent, set:

```yaml
opening_check:
  external_enabled: false
  prompt_file: .agents/opening-prompt.md # optional
```

For a customization example, copy [Shaka's default opening prompt](https://github.com/shakacode/shaka/blob/main/skills/shaka/config/opening-prompt.md)
to `.agents/opening-prompt.md` and edit it for your team. Shaka reads that same
default file when you have not configured a replacement.

For example, a team can develop with Codex and list Claude and Grok in
`review.local_review_agents`. The coding agent tries the listed providers in
preference order. If neither is available, Shaka returns the opening-check
prompt for Codex to apply. With the setting disabled, the coding agent receives
the prompt without sending the opening to another model.

When `external_enabled` is true, the agent uses `review.local_review_agents` in
its existing preference order: a different provider first, then another listed
provider, then the development model when no listed CLI completes the parse.
`external_enabled` defaults to `true`; only a provider in the trusted reviewer
list may receive the opening. A valid `prompt_file`
replaces the default parsing instructions for both external and development-model
checks. Shaka reads it from the trusted default-branch revision, applies the
same file checks as `review.prompt_file`, and treats the PR opening as data.
The required JSON field names and types remain fixed by Shaka.
If the configured check cannot run, the description still publishes and the
development model receives a fallback prompt with the reason.

## `prose_limits`

**Optional.** Shaka refuses to publish a PR description or code walkthrough
that reads as a wall of text. Reviewing a small diff is faster than reading a
long explanation of it, so the text should point to the code instead of
retelling it.

```yaml
prose_limits:
  max_sentence_words: 35
  max_paragraph_words: 100
  max_description_words: 300
  words_per_changed_line: 4
```

The values above are the defaults. Set any key to a positive integer to change
it; omitted keys keep their default. Each limit counts only the prose GitHub
shows. Code blocks, tables, headings, quotes, link addresses, and the body of a
collapsed details block do not count. A collapsed block's summary label counts,
and an inline code span counts as one word.
In a description, only the part Shaka manages counts; text that people or other tools
add outside it is left alone.

- No sentence may run past `max_sentence_words`.
- No paragraph or list item may run past `max_paragraph_words`.
- The whole text may use 150 words plus `words_per_changed_line` for each
  changed line. A 6-line fix allows 174 words; a 100-line change allows 550.
- The description also stops at `max_description_words`, however large the change.

When text breaks a limit, nothing reaches GitHub. The command exits with an
error listing up to three problems and counting the rest. Each problem quotes a long
sentence or paragraph, or states the total word count and its limit. The agent rewrites the text
and runs the command again, so you see only a version that passed. The agent
notes each refusal in the description's collapsed review history, so you can
tell how often the limits fire.

For example, a 19-line change with a 950-word walkthrough is refused. The agent
splits long paragraphs, moves supporting detail into collapsed details, and
links to the code, then publishes again. Shaka reads these values from the
trusted default-branch revision when the agent passes `--ref`; without it, the
defaults apply. If that revision cannot be read, `description` still publishes
under the defaults and its result says why, while `walkthrough` stops.

## Standard command scripts

Connect your existing tools at these fixed paths:

| Script | Required? | Purpose |
| --- | --- | --- |
| `.agents/shaka/bin/setup` | Yes | Install dependencies |
| `.agents/shaka/bin/test` | Yes | Run tests; accept focused arguments |
| `.agents/shaka/bin/validate` | Yes | Complete checks before publishing |
| `.agents/shaka/bin/validate-local` | No | Faster checks before local review |
| `.agents/shaka/bin/trigger-hosted-ci` | No | Start deferred CI after local fixes; requires `validate-local` |

In the older layout, the same scripts live in `.agents/bin/`.

A wrapper can call an existing command. `seam init` generates each required wrapper;
it finds the repository root with Git, so it works from any directory and in linked
worktrees. To run a different command, change only its last line, for example:

```sh
exec bundle exec rake test "$@"
```

`exec` preserves the command's exit status and signals. A symlink to a tracked
executable also works if its directory, environment, and arguments already match.

Scripts must be executable and resolve within the repository. `.agents` and the
directories holding the configuration and scripts must be real directories.
Removing an optional check already on the default branch requires an explicit,
maintainer-approved policy change.

## `base_branch`

**Optional. Default: the repository's default branch.**

Use `base_branch: develop` to start from and target `develop`. An explicit task
choice or existing PR target takes precedence. A base outside the configured or
default branch needs confirmation and uses Ask. Policy always comes from the
default branch.

## `branches.name`

**Optional. Default: `'{login}-{host}/{issue}-{description}'`.**

```yaml
branches:
  name: '{login}-{host}/{issue}-{description}'
```

| Placeholder | Meaning |
| --- | --- |
| `{login}` | Authenticated GitHub login |
| `{host}` | Coding-agent slug, such as `codex` or `claude` |
| `{issue}` | Issue, PR, or work-item number; required in the template |
| `{description}` | Short task description |

For example: `alex-codex/42-fix-search`.

When a task comes from a tracker that offers a branch name, such as Linear's
**Copy git branch name**, the agent uses that name instead of the template.
Trackers link a pull request to its
work item through that branch name. Git must accept the name as a branch name.

## `wip.include_locations`

**Optional. Default: `true`.**

```yaml
wip:
  include_locations: true
```

Include the checkout path and session link in **WIP Details**. `seam init` writes
this value. Set it to `false` to publish both as `UNKNOWN`; ownership, state, and
next action remain visible.

Locations can reveal local names or identifiers. The agent must inspect them for
private information before publishing; Ruby does not check for it. Expandable
sections on public PRs are public too.

## `repo_prefix`

**Optional. Default: a label derived from the repository name.**

Use 1–6 uppercase ASCII letters or digits, such as `repo_prefix: SHOP`, to label
chat titles: `SHOP PR #42 · Fix checkout`. The
[repository catalog](repository-catalog.md) reports duplicate prefixes.

## `version`

**Required. Currently `1`.** This identifies the configuration format, not the
installed Shaka release.

Unknown keys and invalid values produce an error. Link requirements and design
plans from `AGENTS.md`.
