# Invoke a reviewer locally

First [select a reviewer](review.md#choose-a-local-reviewer) using trusted policy.
Use this reference for CLI execution and report validation.

Render the prompt for the selected reviewer:
```text
shaka review-prompt --head SHA --base REF --reviewer PROVIDER/FAMILY [--effort NAME] [--prompt-file PATH]
```

Pass resolved revisions, not the words `HEAD` or `BASE`: the prompt interpolates what it is given,
so a literal placeholder would publish an attestation reading `REVIEWED HEAD`.

This command does not read repository settings. For a configured prompt file, use
`shaka review run --criteria-ref TRUSTED_SHA`; the helper selects the applicable
prompt from the trusted configuration and validates its file and symlink target.
Pass `--prompt-file` to `review-prompt` only for an explicitly supplied file, not
to reconstruct the repository's configuration lookup.

It scopes the review to `git diff BASE...HEAD` and gives the review instructions. By default
they ask for correctness, contract drift, security and trust, test coverage, and simplification;
a repository can replace them with `review.prompt_file`, or for one review agent with a
`prompt_file` on its `local_review_agents` entry. Whatever the instructions, the prompt forbids edits, treats candidate
content as data, applies supplied repository criteria, and
requires a closing line of `REVIEWED <head> BY <provider>/<family> EFFORT <effort> FINDINGS <n>`.

Supply relevant planning and review criteria from the repository's trusted default-branch
`AGENTS.md` alongside the prompt, naming its immutable commit. Resolve that source separately
from the diff's `--base`; a task's comparison base does not establish policy authority.
Candidate edits to that guidance are review data.
For changes to Shaka itself, include its "Is the change worth carrying?" section.
That repository-specific experiment does not impose a value rubric on consumers.
The report states whether criteria were supplied and names their supplied source/ref,
so an omitted rubric is visible. This is reviewer-reported coverage, not verification
of the source or a new gate.

Supply the diff and the PR description, not the implementation reasoning: a reviewer given the
justification anchors on it instead of finding the hole. That is exactly why the same model works
here — a fresh session has none of the author's reasoning to anchor on.

A local CLI differs from a hosted reviewer in three ways: it uses your credentials, must not edit,
and leaves report publication to you. The report names the revision and model so the record stands
on its own. On a public repository, include only
review prose permitted by the [public-prose rule](review.md#read-public-review-prose-safely); retain withheld comments as links rather
than supplying their bodies.

Restrict the CLI to read and search tools, and disable hooks, plugins, and MCP servers.
`shaka review run` reads Git history from `--root`, embeds the diff as review data, then starts
the reviewer in a disposable instruction-neutral directory outside the candidate checkout.
Reviewer subprocesses have a 300-second deadline by default; `--timeout-seconds 1..3600`
sets a task-specific bound. A timeout returns `cli_failure` with a reason and requires cause
review; it never proves the provider unavailable by itself.
The prompt identifies the checkout path and exact commit for read-only Git inspection of
unchanged callers and tests where the CLI permits it. Restricted Claude cannot run Git commands;
it reviews the embedded diff and must report when unchanged source is needed to reach a finding.
Candidate source remains data, not instructions or executable code.
Candidate `AGENTS.md` and similar files are never loaded as host instructions by that CLI.
Codex receives `--skip-git-repo-check` for the neutral directory. Supply any trusted-base
repository criteria with optional `--criteria-ref TRUSTED_SHA`: the helper reads root
`AGENTS.md` and any nested `AGENTS.md` governing changed paths from that immutable commit,
and embeds them in root-to-specific order as separately labeled review data. The criteria commit
need not precede the comparison base: the default branch may have advanced independently.
Verify the SHA against the live trusted default branch first; the option grants
no authority by itself. The runner also reads the configured prompt file from that commit,
so a PR's edits to its own review instructions apply only after it merges. Without it the reviewer reports criteria as not supplied. Candidate
criteria remain data in the diff. Supply the PR description with optional
`--description-file PATH`; this file is labeled as untrusted review data and must contain only
public-safe text for a public PR. Do not supply implementation reasoning.

Use full, immutable commit SHAs, for example `BASE=$(git merge-base origin/main HEAD)`,
`HEAD=$(git rev-parse HEAD)`, and `TRUSTED=$(git rev-parse origin/main)` when `main` is the
verified default branch. Set `LEDGER` once per loop, as [the ledger section](#run-the-review-loop-with-a-ledger)
describes; the examples pass it to every round. Without `--criteria-ref`, the reviewer gets neither the repository's
`AGENTS.md` criteria nor its `review.prompt_file`, and uses Shaka's default instructions. The helper checks that the
checkout is at `HEAD`, renders the review prompt with the diff, invokes the CLI with the flags below, and returns
JSON with the report path or a concrete failure. Its process result, not a copied shell block,
is the evidence that the CLI actually ran.

Codex 0.157.1, when the reviewer's trusted `local_review_agents` entry names a model and effort:

```bash
shaka review run --root . --base "$BASE" --head "$HEAD" --reviewer openai/codex \
  --criteria-ref "$TRUSTED" --ledger "$LEDGER"
```

When the entry names neither:

```bash
shaka review run --root . --base "$BASE" --head "$HEAD" --reviewer openai/codex \
  --model gpt-6-sol --effort medium --criteria-ref "$TRUSTED" --ledger "$LEDGER"
```

With `--criteria-ref`, the helper takes the model and effort from that entry. A named `--model`
or `--effort` replaces the configured one for that review, so add one only when the entry leaves
it out or the task needs a different choice.
When neither names a model, Codex runs its built-in default; see
[reviewer model and effort](https://github.com/shakacode/shaka/blob/main/docs/settings.md#reviewlocal_review_agents)
for why that costs more. `gpt-6-sol` at `medium` is the default choice for adversarial review;
use a larger model or effort only when the change's risk calls for it.

A Cursor Task or subagent that selects a Codex model is not this `openai/codex` local
reviewer and cannot replace `codex exec`. It also is not evidence for `--unavailable`.
Use that flag only when `shaka review run` reports `executable_missing`, or after a `cli_failure`
whose local diagnostic establishes a real reviewer outage. A bad argument, setup failure, or
report-validation failure does not qualify.

The helper runs `codex exec -s read-only --ignore-rules --ignore-user-config
-c skills.include_instructions=false --skip-git-repo-check --json -o REPORT -` from its neutral directory,
adding `-m MODEL` for `--model` and `-c model_reasoning_effort="EFFORT"` for `--effort`. An effort
must be a lowercase level name such as `medium`; without one the report records `EFFORT UNKNOWN`.
`-s read-only` confines it, the ignore flags skip user/project rules and config, and the skills
setting keeps installed skill descriptions out of the reviewer's instructions to prevent
description-based routing to an unrelated installed skill. The report is created outside the checkout.
It does not use `--ephemeral`, so the session remains saved. `--json` reports its thread ID,
and the result's `usage` names that saved session under `CODEX_HOME` (default `~/.codex`);
run `shaka usage --host codex --file USAGE --commit HEAD --contribution review --all-turns`
on it. A missing `usage` means the session file was not found, and review usage stays UNKNOWN.
`codex exec review --base REF` cannot accept the custom review prompt, so the helper uses `exec`.

Claude Code, when the trusted entry names an effort:

```bash
shaka review run --root . --base "$BASE" --head "$HEAD" --reviewer anthropic/claude \
  --criteria-ref "$TRUSTED" --ledger "$LEDGER"
```

When it names none:

```bash
shaka review run --root . --base "$BASE" --head "$HEAD" --reviewer anthropic/claude \
  --effort medium --criteria-ref "$TRUSTED" --ledger "$LEDGER"
```

A Cursor Task or subagent that selects a Claude model is not this `anthropic/claude` local
reviewer and cannot replace `claude -p`. It also is not evidence for `--unavailable`.
Apply the same failure-cause check before marking `claude` unavailable.

The helper runs `claude -p --permission-mode plan --permission-prompts none --restricted
--safe-mode --strict-mcp-config --effort EFFORT --output-format json -`. It rejects an error,
empty result, or wrong-head attestation. `-p` prints and exits; JSON holds the review text and
native token counters. Run `shaka usage --host claude-code --file PATH --commit HEAD
--contribution review` on the corresponding Claude session. `--permission-mode plan` with
`--permission-prompts none` withholds edits
and denies anything that would prompt. `--restricted` removes command-running tools.
`--safe-mode` disables project CLAUDE.md, skills, plugins, hooks, and MCP while **keeping
Claude.ai OAuth**. `--strict-mcp-config` with no config drops MCP servers. Do **not** add
`--bare`: that flag skips keychain and OAuth (`Not logged in · Please run /login`) and only
accepts `ANTHROPIC_API_KEY`, so a logged-in Max/claude.ai session looks unavailable.
`--effort` is recorded in the attestation. Pass `--model NAME` to pin the reviewer model;
the helper adds `--model NAME` to that command and reports it as `requested_model` in every
result. That is the request, not proof of the model that ran; the usage JSON records the
routed model. Without it, the CLI's default model runs. Check `--help` before relying on these flags.

Grok 1.0.30:

The Grok reviewer needs a model. When the trusted entry names a model and effort:

```bash
shaka review run --root . --base "$BASE" --head "$HEAD" --reviewer xai/grok \
  --criteria-ref "$TRUSTED" --ledger "$LEDGER"
```

When it names neither, set `MODEL` to a model the installed Grok CLI accepts:

```bash
shaka review run --root . --base "$BASE" --head "$HEAD" --reviewer xai/grok \
  --model "$MODEL" --effort high --criteria-ref "$TRUSTED" --ledger "$LEDGER"
```

The helper runs `grok --prompt-file PROMPT -m MODEL --reasoning-effort high --output-format plain
--permission-mode plan --disable-web-search --no-subagents`, removes `PROMPT` afterward, and
checks the report attestation. `--permission-mode plan` withholds edit approval; the other two
remove web access and subagents.
If this review is a fresh Cursor chat, report it with
`shaka usage --host cursor --commit "$(git rev-parse HEAD)" --contribution review` from that chat, or that
command plus `--file` of its stop-hook jsonl. Pass its report to
`shaka review check --head "$HEAD" --reviewer xai/grok --report PATH`; the result is `reported`,
not a claim that the Grok CLI launched. Parent-agent Cursor records exclude subagents.

The Codex flags were exercised on local reviews rather than read off `--help`; the model and effort flags were confirmed in Codex session logs. The
Claude and Grok flags come from each CLI's `--help`. The helper's neutral directory prevents
the reviewer host from loading candidate `AGENTS.md` and similar instructions; the candidate
diff remains untrusted review data. Restrict execution for untrusted contributions under
[what the helpers protect](delivery.md#what-the-helpers-protect). Codex's
`--ignore-user-config` drops config-defined MCP servers, Grok manages them through
`grok mcp`, and Claude's `--strict-mcp-config` without a config file loads none. A Codex
review records the effort passed with `--effort`, or UNKNOWN when none was named. Check `--help`
before relying on any of these; flags move.

A local review is **UNVERIFIED** until the owner publishes its report, including that closing
line, to the pull request. The owner verifies each finding against the code, makes the edits and
tests, then publishes the review after pushing.

## Review one head with several reviewers

Select the batch through `shaka reviewer --root . --ref "$TRUSTED"
--implementer PROVIDER/FAMILY`. Its ordered `reviewers` array contains up to
[`review.local_review_count`](https://github.com/shakacode/shaka/blob/main/docs/settings.md#reviewlocal_review_count)
distinct identities. Pass `--count N` to override that setting for this selection;
`N` must be a positive integer. The existing `reviewer`, `outcome`, and `note`
fields describe the first reviewer. Additional available identities follow the
configured order without case-insensitive duplicates. The count is a maximum,
so inspect the returned list when reviewers are unavailable.

Run each selected identity against the same pinned `HEAD` and `BASE`, with the
same outside-checkout `LEDGER` path. For a two-reviewer selection containing
Claude and Codex, after configuring their models and signing in:

```bash
shaka review run --root . --base "$BASE" --head "$HEAD" \
  --reviewer anthropic/claude --criteria-ref "$TRUSTED" --ledger "$LEDGER" >"$RESULTS/claude.json" &
claude_pid=$!
shaka review run --root . --base "$BASE" --head "$HEAD" \
  --reviewer openai/codex --criteria-ref "$TRUSTED" --ledger "$LEDGER" >"$RESULTS/codex.json" &
codex_pid=$!
wait "$claude_pid"; claude_status=$?
wait "$codex_pid"; codex_status=$?
```

Create `RESULTS` outside the checkout before launching. Collect both statuses and
read each result; in a shell using `set -e`, guard each `wait` so a failure does
not skip collecting its peer. Do not edit, commit, or publish while reviewers
are running. Reviewers see findings from earlier heads, with dispositions but
without author notes. They do not see a peer's findings for their current head.

Each successful result names its ledger `round`, assigned in completion order.
Record dispositions using that number in the content JSON, for example
`{"round": 2, "head": "FULL_REVIEWED_SHA", "reviewer": "anthropic/claude", "findings": []}`
for a clean second round. Supply every reported finding for a nonempty report.
Without `round`, recording still targets the last observed round for existing
single-reviewer callers. Include `head` and `reviewer` to reject a mismatched
target. Earlier-head dispositions close when a new batch starts. Finding IDs
follow each reviewer across heads; equal IDs from different
reviewers remain separate findings.

Wait for every selected process, handle every result, and record every completed
review before moving to the fix head. Ruby checks all recorded rounds in the
batch before allowing a new head, including every peer's fix commits. It does
not reserve slots for selected reviewers or launch a batch scheduler; waiting
for all selected processes remains the owner's responsibility.

Writes reload the ledger under a short exclusive sidecar lock and replace the
JSON atomically. Keep its `.lock` file in place until all writers have exited;
deleting it can split the lock between processes. Use one stable ledger path on
a local filesystem supporting file locks and atomic rename. Locks cover writes,
not reviewer execution. A duplicate reviewer/head, replaced history, moved
checkout, or ledger that advanced to another head rejects the stale result
without overwriting valid peer evidence. A rejected write returns `ledger_update`
with the private report and usage paths retained for inspection and cleanup.
A failed process adds no completed
round; inspect its structured failure and any private diagnostic before applying
the established availability fallback. Keep reports and usage files until
publication; a missing report or incomplete disposition blocks evidence checks.

Publish the complete ledger after the final batch. The comment includes every
round, report, and disposition, with totals across reviewers. A fix in any final
batch review requires a later reviewed head before publication. Publishing
checks structure and report attestations; the runner checks Git ancestry.

## Run the review loop with a ledger

Keep every round in one ledger, a JSON file outside the checkout, for example
`LEDGER="$(mktemp -d)/review-ledger.json"`. Pass `--ledger "$LEDGER"` to each
`shaka review run`: a completed round adds its head, reviewer, effort, requested model, report,
prompt source, criteria commit, and usage path. The table's Model column shows only the routed
model you record from native usage. The ledger stays private until you publish it.

The prompt asks for a class on every finding. Handle each by class:

| Class | Meaning | In the loop |
| --- | --- | --- |
| `defect` | Wrong behavior, a security or trust hole, or a broken contract | Reproduce it where practical, fix it in a new commit, review again |
| `risk` | A plausible defect you cannot reproduce | Fix it when the fix is clearly correct; otherwise document it |
| `nit` | Style, naming, simplification, optional tests, docs polish | Document it for a later decision; never fixed in the loop |

After a round with findings, record what became of each one:

```bash
shaka review record --ledger "$LEDGER" --content-file FINDINGS.json
```

```json
{
  "findings": [
    { "id": "F1", "summary": "Exit code is 0 on a failed push", "class": "defect",
      "disposition": "fixed", "commit": "FULL_FIX_SHA" },
    { "id": "F2", "summary": "Rename run_all", "class": "nit", "disposition": "documented",
      "note": "Outside this change" }
  ],
  "model": "gpt-6-sol", "tokens": "41,200"
}
```

`disposition` is `fixed`, with the fix commit's full SHA, or `documented`. The helper refuses a
fixed nit, a count that differs from the report's `FINDINGS n`, and a repeated id. Give a
finding the same `id` when a later round raises it again: the comment then flags a finding that
returned after its fix, a sign the fixes are not converging. Give a new finding an id no
earlier round used: the outcome follows each id's latest disposition, so reusing one for a
different problem can hide an unfixed defect. `model`, `tokens`, `cost`, and
`estimate` are optional, as described below, and a top-level `fallback` sets the fallback notice.

`review run` refuses a new head until every earlier review's findings are recorded. It also
refuses a repeated reviewer/head or a return to an earlier batch head, a head that lacks the last reviewed head or any
recorded batch fix commit, a fix recorded as the head it was found in, and a different `--base`;
after a rebase, start a new ledger. Publishing refuses a final batch that records a fix, because
no later round has reviewed it. The next round's prompt
lists, as review data, every earlier finding's id, class, summary, and latest disposition
(`fixed in SHA`, `documented nit`, `documented risk`), plus the commits since the last
reviewed head. It asks the reviewer to confirm each fix and to review the full diff fresh.
It leaves out each `note`, so the reviewer does not anchor on the author's reasons.

A round whose findings are all documented ends the loop. Push, open or adopt the pull request,
then publish right away:

```bash
shaka review publish OWNER/REPO NUMBER --content-file "$LEDGER"
```

## Publish content

The ledger is the content file. Without one, the content JSON lists `rounds`. Copy each
round's `head`, `reviewer`, `report`, `prompt_source`, and `criteria_ref` from its
`shaka review run` result, and add its `findings` in the shape above. Publishing refuses a
round whose findings do not match its report's `FINDINGS n`, so every finding has a disposition.
It also refuses duplicate reviewer/head pairs, returning to an earlier head, and a fix recorded in the commit its round reviewed. A
content file without a ledger gets only these checks: publishing does not read Git history, so
use `--ledger` when fixes must be proven to follow and reach the reviewed head.
Add `model`, `tokens`, and `cost` from native usage; a missing value renders `UNKNOWN`. Leave
`cost` out unless the host reports a priced route. For a subscription session, put the
`USD estimate` that `shaka usage` reports in `estimate` instead: the table marks it `est.` and
the total calls it an API-equivalent estimate, never a bill. When `shaka reviewer` did not return `different_provider`, add
`fallback` with its `outcome` and one `attempts` entry per reviewer tried, copying each
`reviewer`, `failure_stage`, and `reason` from its `shaka review run` result. Leave
`attempts` empty when selection tried no other reviewer. The helper replaces each `reason`
from its first absolute or home-directory path onward with `[path]`, so a setup failure does
not publish a local file location.

```json
{
  "rounds": [
    { "head": "SHA", "reviewer": "openai/codex", "report": "/tmp/shaka-review-x.md",
      "prompt_source": "Shaka default", "criteria_ref": "TRUSTED_SHA",
      "model": "gpt-5.5", "tokens": "41,200", "estimate": "$0.17",
      "findings": [
        { "id": "F1", "summary": "Rename run_all", "class": "nit", "disposition": "documented" }
      ] }
  ],
  "fallback": { "outcome": "same_provider", "attempts": [
    { "reviewer": "xai/grok", "failure_stage": "executable_missing", "reason": "grok is not on PATH" }
  ] }
}
```

The helper checks that each report closes with the attestation for its round. Reports are
published verbatim, so before posting it asks GitHub to render the comment and refuses when an
unclosed code fence or a stray disclosure tag in a report would hide the attestation. The
check cannot stop two reports that together imitate a round's layout, for example a reviewer
steered by the PR it reads. The attestation and the summary table stay authoritative, because
the helper writes both itself. It renders a `Local Adversarial Review`
comment: a summary table; a total of rounds, tokens, and cost; why the loop stopped; what the
Prompt column means; any reviewer fallback notice; each report collapsed with its findings'
dispositions and fix commits; and the last
round's attestation as the final line, where `merge` reads it. A commit GitHub does not have,
such as one a rebase replaced, is named without a link. Publishing again replaces
that comment rather than adding another. Record available native
model, effort, and usage with `shaka usage --commit "$(git rev-parse HEAD)" --contribution review` on the
reviewer's source; missing evidence is UNKNOWN. Add `--format json` to each `shaka usage`
command in this guide and put its `record` in the description's `usage.records`. Do not publish raw sessions or private
context. A recovery
note's `Thread` field follows its [publication
rule](delivery.md#recover-an-unfinished-pr).

Automated review comments are advice, not merge permission. Required GitHub
approvals and checks remain gates. The merge helper checks native readiness and
the current commit; it does not read or judge review findings for the agent.
No extra approval, review receipt, or review service is introduced.

For example, a repo that already runs Claude on PRs can pin the report author in
its trusted `AGENTS.md` seam:

```markdown
Review: use our existing Claude Code Review GitHub workflow. Read its comments
and inline threads from the pinned `claude[bot]` report author, address demonstrated
defects, and recheck fixes before merge.
```

The [React on Rails review workflow](https://github.com/shakacode/react_on_rails/blob/e3d95bebc743ea9f9ab322f4b370667393c7627a/.github/workflows/claude-code-review.yml)
is an example: it posts comments and inspects Claude's execution result because
an unsuccessful review can otherwise report a successful action. Its separate
`@claude` workflow is a different capability, not required by this ordinary path.
