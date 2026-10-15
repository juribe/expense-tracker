---
name: tdd-workflow
version: 0.2.0
description: Mandatory test-driven development workflow for code changes with an HTML plan/results report. Use when making any code changes, feature additions, bug fixes, or refactoring that involves writing or modifying implementation code.
---

# TDD Workflow

## When to Use This Skill
Use this skill when the user requests any code changes, feature additions, bug fixes, or refactoring that involves writing or modifying implementation code. This skill defines the mandatory test-driven development process that must be followed WITHOUT EXCEPTION.

## Core Principle
**YOU MUST WRITE TESTS BEFORE ANY IMPLEMENTATION CODE.**

## Response Style
- Keep the tone of responses calm and focused on the technology
- Avoid the use of exclamatory statements

## Terminal Usage
- Reuse the same terminal for sequential commands (bin/rails test, rails, etc.)
- This project uses minitest with the standard Rails layout (`test/controllers`, `test/models`, `test/integration`, `test/system`, etc.)

## Pre-Flight Checklist
Before making ANY change, you MUST:

### 1. Identify the change type:
- [ ] New feature (requires full TDD workflow)
- [ ] Bug fix (requires test first, then fix)
- [ ] Refactor (requires existing tests to pass)
- [ ] Test-only change (no implementation)
- [ ] Documentation only (skip TDD)
- [ ] UX Experiment (skip TDD - wait until design is resolved before writing tests)

### 2. Review existing test coverage:
- [ ] Check if system/integration tests exist for this workflow
- [ ] Determine if system/integration tests need updates
- [ ] Note any integration test changes needed

### 3. State your plan explicitly:
- [ ] List which test files you'll create/modify (controller, model, and if needed, system/integration)
- [ ] List which implementation files will be affected
- [ ] Declare the TDD steps you'll follow

### 4. Prepare TDD plan report (before confirmation):
- [ ] Build the TDD report data in "plan" phase (see "TDD Report Generation")
- [ ] List the tests you will write, grouped by test class, each with a brief plain-language explanation (max 2 phrases) and why it matters (what error/regression it prevents)
- [ ] List the test files and the implementation files affected, and the TDD steps you'll follow
- [ ] Generate the plan preview HTML at `.tmp/tdd-report.html` (write the plan JSON, then run the renderer — see "TDD Report Generation" → Implementation), then output ONLY one line: `Plan TDD: .tmp/tdd-report.html (tests planificados=N)` so the user can open it in the browser
- [ ] Do NOT modify test structure just for reporting; reuse natural test classes, test methods, and setup blocks as scenario boundaries
- [ ] Keep scenarios marked as "planned"/"unverified" until actual test execution in this run updates their status

### 5. Get user confirmation:
- [ ] Ask: "Does this plan look correct (see the HTML plan report at `.tmp/tdd-report.html`)? Should I proceed with Step 1 (writing tests)?"

**VIOLATION CHECK:** If you find yourself writing implementation code without tests, STOP IMMEDIATELY and revert your approach.

## Step-by-Step Workflow (DO NOT SKIP STEPS)

### Step 1: Write Controller Tests
- Write minitest controller/integration tests for individual actions FIRST (in `test/controllers` or `test/integration`)
- Test action behavior, template rendering, instance variables, redirects
- DO NOT write any implementation code yet
- As you define scenarios (test methods, setup contexts), record them in the TDD report as unverified: include title, plain-language behavior explanation (max 2 phrases), why it matters (what error/regression it prevents), relevant examples (input/expected) if helpful, behaviors to verify, group name/description, and target test file
- Present the tests to the user

### Step 2: 🛑 MANDATORY CHECKPOINT - Request Test Review
**STOP HERE and ask:** "I've written the controller tests above. Please review them before I proceed to model tests."
- DO NOT PROCEED until the user approves
- This is not optional - you MUST wait for user feedback

### Step 3: Write Model & Concern Tests
- Write minitest tests for business logic changes (in `test/models`)
- Include model validations, associations, methods
- Still NO implementation code
- Record any new scenarios in the TDD report as unverified with the same fields (max 2-phrase explanation, why it matters, examples if helpful)
- Present the tests to the user

### Step 4: 🛑 MANDATORY CHECKPOINT - Request Test Review
**STOP HERE and ask:** "I've written the model tests above. Please review them before I proceed to implementation."
- DO NOT PROCEED until the user approves
- This is not optional - you MUST wait for user feedback

### Step 5: Implementation
- ONLY NOW write the minimal code to make tests pass
- Controllers, views, models, routes, migrations
- Always insert or update the initial comment that describes model purpose and methods

### Step 6: 🛑 MANDATORY CHECKPOINT - Final Implementation Notes
**STOP HERE and ask:** "I've written the implementation above. Please review them before I proceed to refactor."
- DO NOT PROCEED until the user approves
- This is not optional - you MUST wait for user feedback

### Step 7: Refactor
- Clean up code for readability
- Extract complex logic to properly named methods
- Ensure code follows standards (see ruby-standards and rails-standards skills)

### Step 8: Update System/Integration Tests (if needed)
- Update or create system/integration tests if the user workflow changed
- Run these integration tests to verify end-to-end functionality
- Present any new system tests to the user

### Step 9: Quality Checks
- Run the full test suite with `bin/rails test`
- Capture test execution results for scenarios identified in this TDD cycle. For each scenario, record status (passed/failed/skipped), actual behavior (got/expected) only where relevant, and concise failure error info (without full stack traces). Do NOT guess results for unverified scenarios.
- Fix any failures or errors
- If a new test run occurs, update the TDD report with verified results. If no new test run occurred, do NOT fabricate results.
- **Update the TDD HTML report to the results phase** (see "TDD Report Generation" section) using collected data, overwriting `.tmp/tdd-report.html` via the renderer. The report must distinguish verified behaviors from unverified ones.
- Report results to the user AND output **only one line** at the end: `TDD report: .tmp/tdd-report.html (passed=X, failed=Y, skipped=Z, total=T)` - where counts reflect only scenarios actually verified in this execution. Do not add extra explanation.
- **🛑 CRITICAL CHECKPOINT RULE**: If you attempt to fix failing tests and they fail a SECOND time, you MUST STOP IMMEDIATELY and ask the user to review. DO NOT make a third attempt without user approval.
    - First failure: Analyze and attempt a fix
    - Second failure: **MANDATORY STOP** - Present the error and ask: "The tests failed again after my fix attempt. Please review the error above before I continue."
    - DO NOT proceed until the user explicitly approves the next approach

## What NOT to Do

- ❌ Never write implementation code before tests
- ❌ Never skip the three checkpoint reviews
- ❌ Never assume test approval - always ask explicitly
- ❌ Never write code without corresponding tests (except trivial changes, documentation, or UX experiments)
- ❌ Never proceed past a checkpoint without user confirmation
- ❌ Never use `reload` in controller implementations to fix test failures - it should never be necessary and indicates a test timing issue

## TDD Report Generation

### Purpose
Generate a static, self-contained, visual HTML report at `.tmp/tdd-report.html` (or equivalent temp location not tracked by Git) that explains functional behavior tested, without translating test names verbatim. Prioritize readability with cards, visual indicators, and collapsible sections. The report has two phases that share the same file and template:

1. **Plan preview** (Pre-Flight step 4, before the user confirms Step 1): shows the plan and the tests that will be written, so the user can review them in the browser instead of the CLI.
2. **Results** (Step 9, after running the suite): updates the same report with actual execution results per scenario.

### Constraints
- Use the fixed template at `.opencode/skills/tdd-workflow/tdd-report-template.html`. Do not invent external dependencies, images, or other models.
- Only populate explanations: max 2 phrases per scenario. Keep brief.
- Distinguish verified vs unverified behaviors. Never invent coverage or results.
- If no new test execution occurred, do not generate fictitious results or mark tests as passed: keep the report in "plan" phase.
- Do not include full test code or extensive traces. Only include concise failure details (expected/got/error relevant).
- Reuse data collected during test writing and execution; do not re-read all files or re-run tests solely to generate the report.
- After generating, output only a single line:
  - Plan phase: `Plan TDD: .tmp/tdd-report.html (tests planificados=N)`
  - Results phase: `TDD report: .tmp/tdd-report.html (passed=X, failed=Y, skipped=Z, total=T)`

### Implementation
- The model only produces the JSON data. Write it to a temp file (e.g. `.tmp/tdd-report-data.json`), then render the HTML with the deterministic script:
  `ruby .opencode/skills/tdd-workflow/render_tdd_report.rb .tmp/tdd-report-data.json .tmp/tdd-report.html`
- The renderer injects the JSON into the fixed template `.opencode/skills/tdd-workflow/tdd-report-template.html`. Do NOT hand-edit the template or the generated HTML.
- Ensure the generated report is valid HTML, self-contained, and readable in the browser.
- Do not expand the skill's core instructions unnecessarily; keep this logic separate from the workflow steps.

### Plan phase data (`phase: "plan"`)
- `phase`: `"plan"`
- `generatedAt`: ISO timestamp
- `sourceFile`: e.g. `"plan (pre-implementación)"`
- `plan`: `{ changeType, summary, testFiles[], implFiles[], steps[] }`
  - `changeType`: from the Pre-Flight classification (e.g. "New feature", "Bug fix")
  - `summary`: one short paragraph describing what will be built and verified
  - `testFiles`: test files to create/modify
  - `implFiles`: implementation files that will be affected
  - `steps`: the ordered TDD steps for this change
- `summary`: `{ total: N, passed: 0, failed: 0, skipped: 0 }` (results stay at 0 in plan phase)
- `verifiedGroups`: `[]`
- `unverified`: array of planned tests, each `{ title, group, plainLanguageExplanation, whyItMatters, file }`. `group` becomes the test class / describe-equivalent grouping in the report.

### Results phase data (`phase: "results"`)
- `phase`: `"results"`
- `generatedAt`: ISO timestamp
- `sourceFile`: the test command / run label
- `summary`: `{ total, passed, failed, skipped }` (only verified scenarios counted)
- `verifiedGroups`: `[ { name, description, file, scenarios: [ { title, plainLanguageExplanation, whyItMatters, examples[], behaviorsVerified[], file, status, failure } ] } ]`
  - `status`: `"passed" | "failed" | "skipped"`
  - `failure`: `{ expected, got, error }` only for failed scenarios, concise (no full stack traces)
- `unverified`: scenarios identified but not executed/verified in this run, same shape as plan phase

### Data to include in the report
- **Summary**: passed, failed, skipped, total (verified only, results phase).
- **Verified groups**: scenarios with actual execution results, grouped by test class / setup context. Each scenario: title, plain-language explanation (max 2 phrases), why it matters, examples (input/expected) when helpful, behaviors verified, file (test path), status, and failure details if failed.
- **Unverified / planned**: grouped tests with title, explanation, why it matters, and file, without status.
- **Failures detail**: highlight failed scenarios with expected/got/relevant error.

## Context & Standards References
Before changing code, scan the nearest `README.md` (root and feature-level) for principles, stack constraints, and product quirks relevant to that area.

## Related Skills
- Use `project-context` skill for branch strategy and environment info
- Use `rails-standards` skill for Rails-specific conventions
- Use `ruby-standards` skill for Ruby language conventions
- This project uses minitest, not RSpec. Follow the existing tests in `test/` for minitest conventions