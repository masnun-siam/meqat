# Engineering workflow

> Repo copy of the ai-workflow plugin guide. Only deviation: the board (GitHub project "Personal" #4) has no Backlog status, so new issues start in **Todo**.

How a piece of work moves from an idea to a merged pull request, for people and for AI agents. The repository's `CLAUDE.md` or `AGENTS.md` holds its rules; this guide holds the detail. The skills in this plugin are the step-by-step procedures for each stage and point back here. Where a skill and this guide disagree, the skill wins and this guide is the thing to fix.

## Repository settings

### Base branch

Every skill branches from, compares against and opens pull requests into the base branch. Resolve it once per session, in this order:

1. The base branch named in the repo's `CLAUDE.md` or `AGENTS.md`.
2. Otherwise the first of `staging`, `stage`, `dev` that exists on the remote (`git ls-remote --heads origin <name>`).
3. Otherwise the GitHub default branch (`gh repo view --json defaultBranchRef -q .defaultBranchRef.name`).

When the answer came from step 2 or 3, tell the user which branch was used and ask them to write it into `CLAUDE.md` or `AGENTS.md`.

The production branch (for example `master` or `main`) is the one the base branch is released into. When the base branch is the default branch, there may be no separate production branch.

### Repo guides and templates win

Before using a guide or template from this plugin, look for the repo's own: the references in `CLAUDE.md` or `AGENTS.md`, then `docs/guides/<name>.md` and `docs/templates/<name>.md`. Use the repo's copy when it exists; otherwise use the plugin's (`guides/` and `templates/` at the plugin root).

The same goes for conventions: anything the repo's `CLAUDE.md` or `AGENTS.md` states (branch names, commit format, paths, labels) overrides the defaults below.

### Repo skills win

Before you run another of this plugin's skills, look for the repo's own copy at `<repo root>/.claude/skills/<name>/SKILL.md`, where `<repo root>` is the top of the git worktree you are working in. Check it with Read or Glob. If the file exists, run `/<name>`; otherwise run `/ai-workflow:<name>`. Every hand-off in these skills and guides means this check, whichever spelling it is written in (`/<name>`, `/ai-workflow:<name>` or `ai-workflow:<name>`).

Agents (`peer-reviewer`, `worklog-runner`) are always the plugin's. One line is exempt and keeps its exact text: dump's `→ next: /create-prd <folder>`, which flow reads byte for byte; flow's own hand-off then follows this rule.

### Area docs

Skills often say "the repo's docs for each area touched". Find them from the references in `CLAUDE.md` or `AGENTS.md`, then under `docs/`. If the repo has none, read the code next to the change and follow it.

## Stages

| Stage | Output | Skill |
|---|---|---|
| 1. Product requirements | A PRD: what, why and the technical design, with no open questions. On approval, one GitHub epic | `/create-prd` |
| 2. Tasks | One child issue of the epic per task, small and verifiable, split so several engineers can work at once, with native blocked-by links | `/create-tasks` |
| 3. Refined issues | Each issue body rewritten with WHAT, WHY and HOW, labelled `refined`, moved from Todo to Ready on the board once no blocker is open (the epic to In progress) | `/refine-issues` |
| 4. Implementation | A worktree, a branch and a PR into the base branch that closes the issue: draft first, reviewed with `/pr-review`, ready when CI is green; after the merge the issue is closed and set to Done. `/implement-issue <epic>` picks the lowest-numbered Ready issue. Independent issues run in parallel, one worktree and dev stack each | `/implement-issue` |
| 5. Local verification | Evidence that every relevant check passes | `/verifier-locally` |
| 6. Review | Findings with evidence and a verdict | `/pr-review` |
| 7. Release | A base-branch to production-branch release PR, opened by a human | none |

Work on anything that is not trivial starts from a refined issue. If there is no issue, or it has no acceptance criteria, stop and ask for one instead of guessing the requirements.

## PRDs

- Template: `templates/prd.md`. PRDs live in `docs/prds/<slug>.md` unless the repo says otherwise.
- **The PRD is the source of truth.** The issues are derived from it. A decision that is not in the PRD has not been made, and nobody settles one in an issue, a pull request or a chat thread instead.
- **It holds the technical design as well as the product behaviour.** There is no separate technical spec: data, API contract, backend, frontend, realtime, rollout and testing are sections of the PRD.
- **Decisions, not code.** The technical design stays at the level of contracts and behaviour: what is costly to change later, or what two engineers must agree on to work apart. Endpoints, fields, tables and collections are named. File paths, class and method names, signatures, step-by-step logic and test file names are not: they bury the decisions a reviewer has to judge, they go stale as the base branch moves, and they are worked out when the issues are written.
- **Diagrams where they help.** A PRD uses Mermaid diagrams beside the text wherever a picture is easier to read and discuss, and always for a big feature: user flows, exchanges between parts, lifecycles, the data model. A diagram supports the text and never replaces a requirement.
- **It has no open questions when it is approved.** Whoever writes it asks every question up front, each with a recommendation and its reason, and records the answers under "Decisions". A question found during implementation can change issues that are already in progress, which is what this rule prevents.
- Every requirement is numbered (`FR-1`, `FR-2`) and has an acceptance line someone could test.
- Each PRD gets a slug (for example `conversation-tags`). The same slug names the label `prd-<slug>` that ties its issues together.
- Status moves `Draft` → `In review` (a pull request into the base branch is open for the team) → `Approved` (a human says the team has reviewed it). Approval creates the epic.
- A PRD has one epic unless the team asks for more. More than one is for a feature that ships in separately releasable parts; each epic lists the `FR-n` it covers.
- **Changing an approved PRD.** Change the PRD first, add a line to its "Change log" with the reason and the issues affected, then update those issues to match.

## Tasks

- `/create-tasks` splits an approved PRD into tasks and creates each one directly as a child issue of the PRD's epic. There is no separate task-list file.
- The split makes no design decisions of its own. If it shows a decision is missing or wrong, the PRD is changed first.
- Every `FR-n` is covered by some task, and no task adds anything the PRD does not ask for.
- **Keep tasks small.** A small task is quick to review and easy to verify, and a wrong one is cheap to redo. A task is too big, and is split, when any of these is true:
  - it delivers more than one outcome, or its outcome needs "and" to describe
  - it spans more than one area of the codebase (for example backend and frontend)
  - it has more than about five acceptance criteria
  - it changes more than about five files, tests not counted
  - it cannot be proven by one scoped verify command

  The lower limit: a task must be mergeable alone with the build green and have a test of its own. The numbers are a guide for the split, not a gate on the pull request.
- **Split for several engineers.** The goal is the widest set of tasks that can be in progress at once without two pull requests editing the same file:
  - Put what everything else builds on (schema, shared types, the API contract's route and response shape) in the smallest possible first tasks, so the rest can fan out behind them.
  - Find the existing files more than one part of the work must edit (routes, shared types, navigation and the like). Give each to exactly one task, or order the tasks that need it with a dependency.
  - Prefer short dependency chains. A task is blocked only by the tasks it cannot be merged without, never in a cycle.
  - The PRD fixes the API contract, so a frontend task whose tests mock that contract can run at the same time as the backend task behind it.
- **When an approved PRD changes**, the affected issues are updated after confirmation, with a comment saying what changed and why; a task that is no longer needed is closed with the reason.

## Refined issues

A refined issue is one an engineer or agent can implement without asking anything or searching for what was already known. `/create-tasks` creates the issue; `/refine-issues` fills it and adds the `refined` label. Template: `templates/issue.md`.

| Section | Holds |
|---|---|
| WHAT | The outcome in one or two sentences, the acceptance criteria as testable statements, and what is out of scope for this issue |
| WHY | The problem it solves for the user, and the PRD requirements it covers, quoted, with the PRD path |
| HOW | The files and symbols to change or create; the existing code to follow as precedent; the data, API contract and behaviour from the PRD it must match, quoted; edge cases and data isolation; the tests to write; how to verify it locally, including the commands and, for user-facing changes, what to check in the running app; and what it depends on from its blockers |

- **The issue carries the context, so the implementer does not have to find it again.** Whoever refines it opens the code first: every file it cites, the precedent it copies, the tests next to it and the callers of anything it changes. Every cited path is real or marked new.
- **It stands alone.** The parts of the PRD the issue needs are quoted in it, so it can be implemented without opening anything else. The PRD stays the source of truth: if the two disagree, the PRD wins and the issue is fixed.
- **Priority** is the PRD's, applied as one `priority:` label to the epic and every issue under it. Order within the epic comes from the blocked-by links, not from title prefixes.
- **Assignees** are left empty unless the user names them. Engineers pick from the issues that are not blocked.
- An issue that is closed or has a pull request open is not edited without asking.

## GitHub: project, epics and dependencies

Relationships between issues are recorded with GitHub's own features, so the board and the issue page show the order of work. Labels and text in the body do not replace them.

| What | How |
|---|---|
| Epic | An issue titled `Epic: <title>`, labelled `epic` and `prd-<slug>`, from `templates/epic.md`. Created by `/create-prd` when the PRD is approved; `/create-tasks` creates it only if it is missing. |
| Task issue | Titled `<Feature>: <summary>`, labelled `prd-<slug>` and the PRD's `priority:` label, plus the area and type labels the repo already uses. |
| Task belongs to an epic | Native sub-issue: `gh issue create --parent <epic>`, or `gh issue edit <n> --parent <epic>` for an existing issue. |
| Task waits for another | Native dependency: `gh issue create --blocked-by <n>,<m>`, or `gh issue edit <n> --add-blocked-by <m>`. The body still says `Depends on #<m>` for readers. |
| Reading them back | `gh issue view <n> --json parent,subIssues,blockedBy,blocking` |

**Finding the project.** Never hard-code a project name or number; read it from where the team's issues already are:

1. List the projects recent issues sit on: `gh issue list --state all --limit 50 --json number,projectItems`. Look at epics first (`--label epic`), then at all issues.
2. One project in use: add the new issues to it with `gh issue create --project "<title>"`, or `gh issue edit <n> --add-project "<title>"`.
3. More than one in use: ask which, recommending the one the most recent issues of the same kind are on.
4. None in use: check `gh project list --owner <owner>`. Propose a project if exactly one is open; otherwise skip the project step and say so in the report. Do not create a project.

**Project fields.** After adding an issue or an epic, set its status to Todo (`gh project field-list`, then `gh project item-edit`). **Ready** means an agent can start it now: the issue is open, labelled `refined`, and every issue in its `blockedBy` is closed. `/refine-issues` moves a refined issue from Todo to Ready when it meets that condition, and the epic to In progress; `/implement-issue` moves the rest from Todo to Ready once they meet it, as their blockers close. Leave iteration and every other field to the team unless the user says what to set.

Project commands need the `project` scope on the `gh` token (`gh auth refresh -s project`). If it is missing, say so and carry on without the project step instead of failing.

## Implementation

- **A blocked issue is not started.** If any issue it is blocked by is still open, the work stops there and the user is told which ones.
- **One worktree per issue**, under `.worktrees/<n>-<short-slug>`, branched from the latest `origin/<base>`. The main checkout is never the place of work, so several issues can be in progress on one machine. Issues with no open blocker between them can be worked in parallel, one session each, with a dev stack of its own (own ports and data) if the repo supports one; if it does not, only one dev stack runs at a time. The worktree gets its dependencies installed, and a bug is reproduced there before it is fixed; if it does not reproduce, the work stops and the user is asked.
- **Local first.** Every check that can run locally runs locally and passes before a push. CI confirms; it is not where failures are found. Each push starts a full CI run, and so may each edit to a PR's title or body; after a base-branch change a push may be needed to run CI against the new base.
- **Verified in the running app.** Beyond the tests, the change is exercised against the local app: in a browser for anything a user can see, through the endpoint, job or command otherwise. What was checked is written in the PR.
- **Code quality.** The codebase has to stay consistent, maintainable and reliable, so new code is held to this:
  - Reuse before writing. Look for an existing helper, service, query scope, component or hook that already does the job, and use it.
  - No duplication. Logic that would exist twice after the change is extracted and shared. Duplication that was already there and is not in the way becomes a follow-up issue.
  - Consistent with its surroundings: the names, layering, response shapes and error handling of the files next to it and of the area's docs. No new pattern where one exists.
  - Simple and readable: small functions with one job, names that say what they mean, no cleverness a reviewer has to decode.
  - Nothing left behind: no dead or commented-out code, no debug output, no abstraction that nothing uses yet.
  - Reliable: errors and empty cases are handled, not assumed away, and every path a test can reach has one.
- **Data isolation.** If the project is multi-tenant or has per-user data, every query, endpoint, job and broadcast is scoped as its rules require.
- **Documentation moves with the code.** The same PR adds, updates or removes the documentation its change makes missing, wrong or dead.
- **Found on the way.** A bug, a refactoring opportunity or a gap that can wait becomes a GitHub issue at once, in two steps (a bug or failing check is reproduced first, locally or in CI, and filed with its evidence): `/create-tasks` creates it (linked to the issue it was found under), then `/refine-issues <n>` fills it (see "Repo skills win"). It is not fixed in this PR. One that blocks the issue is fixed in this PR, as small as possible, in its own commit, and named in the PR body.
- **Corrections travel across the epic.** Wrong, stale or outdated information found in another issue of the same epic, including what the current change has just made untrue, is commented on that issue at once: the line that is wrong, what is true now, and where it was found. Whoever starts an issue reads its comments first. The issue body is corrected later by `/refine-issues`.
- **Review, then one CI run.** CI is expensive, so the branch is reviewed with `/pr-review` (see "Repo skills win") locally, after the local checks and before the first push, and its Critical and Major findings are fixed there. The latest `origin/<base>` is merged in just before that push, since two PRs green on their own can still break the base branch together. The PR is opened as a draft and marked ready only when CI is green, with the new tests seen passing and not skipped in the job log, and every finding, comment and review on it, from people and bots, has been fixed or answered.
- **Learning log on the issue.** What the work teaches that the issue did not say goes on the issue as a short comment at the time: what was found and what was done. It is not a progress report.
- **Cleanup after the merge.** When told the PR is merged, the session confirms it was merged into the base branch and that the base branch holds the branch's content (a squash merge leaves the branch's commits out of its history). Only then is the issue closed, if the merge did not close it (a PR into a base branch that is not the default branch does not), and set to Done. The session's own dev stack, if it had one, is stopped and released, the worktree and the local and remote branch are removed, and the main checkout is put on an up-to-date base branch. Each issue the merge unblocked is moved to Ready and told on GitHub that it can start.
- **No decisions in the middle.** If the issue is wrong or silent, the work stops and the answer goes into the PRD first.

## Branches, commits and pull requests

- Branch from the latest `origin/<base>`, named `issue-<n>-<short-slug>` (for example `issue-42-export-csv`).
- Never commit or push to the base branch or the production branch.
- Commit subject: `<type>(#<issue>): <summary>`, for example `fix(#42): escape commas in CSV export`.
- One issue per PR unless the issues cannot be separated. Keep unrelated cleanups out; they become follow-up issues.
- The PR goes into the base branch. Its body is never empty and references its issue (`Closes #123`).
- A PR body states: what changed and why, how it was verified (commands and results), decisions a reviewer would question, and anything operations must do before or after merge.
- An agent never merges a PR and never opens the release PR from the base branch to the production branch.

## Gates

Checks run in up to three places: commit hooks, push hooks and pull-request CI. Find them in the repo (`.pre-commit-config.yaml`, `.husky/`, `lefthook.yml`, `.github/workflows/`, the `Makefile`). None may be bypassed or weakened: no `--no-verify`, no lint or type suppressions, no edits to hooks or CI to make a failure go away.

Hooks only run in a clone where they are installed; check that the file printed by `git rev-parse --git-path hooks/pre-commit` exists before trusting a commit.

When a gate fails, read the whole output, find the cause and fix that. After three failed attempts at the same gate, stop and report what you tried.

## Lessons

`tasks/lessons.md` records non-obvious things learned about the codebase and its tooling. Skim the sections for your area before starting, and add an entry when a correction or a surprising failure taught something a future session would otherwise repeat.

Keep the kinds of learning apart:

| Learned | Goes in |
|---|---|
| Something specific to one issue: a wrong assumption, a deviation from its plan | a comment on that issue |
| Something about the code, a library or the tooling that the next issue would hit too | `tasks/lessons.md` |
| A convention the team follows | the repo's docs |
| A better way to run one of the procedures | the skill itself, see the ai-workflow plugin's `guides/skills.md` |
