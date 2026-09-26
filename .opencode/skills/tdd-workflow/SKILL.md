---
name: tdd-workflow
version: 0.1.0
description: Mandatory test-driven development workflow for code changes. Use when making any code changes, feature additions, bug fixes, or refactoring that involves writing or modifying implementation code.
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
- Reuse the same terminal for sequential commands (rspec, rails, etc.)

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
- [ ] Check if system/request tests exist for this workflow
- [ ] Determine if system/request tests need updates
- [ ] Note any integration test changes needed

### 3. State your plan explicitly:
- [ ] List which test files you'll create/modify (controller, model, and if needed, system/request)
- [ ] List which implementation files will be affected
- [ ] Declare the TDD steps you'll follow

### 4. Get user confirmation:
- [ ] Ask: "Does this plan look correct? Should I proceed with Step 1 (writing tests)?"

**VIOLATION CHECK:** If you find yourself writing implementation code without tests, STOP IMMEDIATELY and revert your approach.

## Step-by-Step Workflow (DO NOT SKIP STEPS)

### Step 1: Write Controller Tests
- Write RSpec controller specs for individual actions FIRST
- Test action behavior, template rendering, instance variables, redirects
- DO NOT write any implementation code yet
- Present the tests to the user

### Step 2: 🛑 MANDATORY CHECKPOINT - Request Test Review
**STOP HERE and ask:** "I've written the controller tests above. Please review them before I proceed to model tests."
- DO NOT PROCEED until the user approves
- This is not optional - you MUST wait for user feedback

### Step 3: Write Model & Concern Tests
- Write RSpec tests for business logic changes
- Include model specs, validations, associations, methods
- Still NO implementation code
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

### Step 8: Update System/Request Tests (if needed)
- Update or create system/request tests if the user workflow changed
- Run these integration tests to verify end-to-end functionality
- Present any new system tests to the user

### Step 9: Quality Checks
- Run full test suite with `bundle exec rspec`
- Fix any failures or errors
- Report results to the user
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

## Context & Standards References
Before changing code, scan the nearest `README.md` (root and feature-level) for principles, stack constraints, and product quirks relevant to that area.

## Related Skills
- Use `rspec-standards` skill for RSpec syntax and patterns
- Use `ruby-standards` skill for Ruby language conventions
- Use `rails-standards` skill for Rails-specific conventions
- Use `system-test-patterns` skill when writing system/browser tests
- Use `project-context` skill for branch strategy and environment info