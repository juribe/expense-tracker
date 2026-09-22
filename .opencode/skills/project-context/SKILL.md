---
name: project-context
version: 0.1.0
description: Project technical environment, conventions, and standards. Use to understand project context before making code changes, or when needing to locate README files and project-specific conventions.
---

# Project Context

## When to Use This Skill
Use this skill to understand the project's technical environment, conventions, and standards before making code changes.

## Required Reading

Before changing code in any area, read the relevant README files in the project:

### Root README
**Action:** Read `/README.md` at the start of each session.

This typically contains:
- Application overview and purpose
- Technical stack and versions
- Branch strategy
- Code standards and conventions
- Setup instructions

### Feature-Level READMEs
**Action:** Check for a README in the directory you're editing (e.g., `/app/features/billing/README.md`).

These may contain:
- Feature-specific conventions
- Domain concepts and terminology
- Known constraints or quirks

### Priority
1. Always read root README first for project-wide standards
2. Check for feature-level README in the area you're working
3. Feature-level guidelines take precedence when they conflict with root

## When Context is Missing

If README files don't contain information needed for a task:
1. Ask the user for clarification
2. Follow existing patterns in the codebase
3. Suggest updating the README after the task is complete

## Related Skills
- `tdd-workflow` - Development process
- `ruby-standards` - Ruby language conventions
- `rails-standards` - Rails-specific conventions
- `rspec-standards` - Testing patterns
- `system-test-patterns` - Browser testing
