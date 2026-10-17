# AGENTS.md — Expense Tracker

## 1. Project Overview

This project is a personal Expense Tracker built with:

- Ruby on Rails 8
- PostgreSQL
- Action Cable
- Solid Queue for background jobs
- Solid Cache for caching
- Minitest for testing

The application manages personal finances, including expenses, income, money sources, transfers, credit cards, revolving credit, loans, savings goals, recurring obligations, financial reports, and AI-assisted expense capture.

The main priorities are financial accuracy, clean code, maintainability, data integrity, and a clear user experience.

## 2. Mandatory Skills

Three primary skills define the development workflow:

- **Rails skill:** Rails conventions, application architecture, framework features, and established project patterns.
- **Ruby skill:** Idiomatic Ruby, clean code, maintainable abstractions, and appropriate object-oriented design.
- **TDD skill:** Test-driven development, including writing or updating tests, running them, and verifying the implementation.

### Rules

1. Identify which skills apply to the task.
2. Read and follow the relevant skill instructions before implementing changes. For Rails and Ruby changes, consult both relevant skills. Use TDD for behavioral changes, bug fixes, and new functionality.
3. Do not duplicate detailed skill instructions here. This file defines project-wide expectations; the skills define their implementation workflows.
4. Do not claim to have followed a skill unless its instructions were actually consulted and followed.
5. Do not skip TDD because a change appears small.
6. Follow the actual skill instructions and the project's existing conventions.
7. If a skill conflicts with an explicit project requirement, follow the project requirement and explain any significant conflict.

## 3. Graphify — Codebase Knowledge Graph

This project uses Graphify to maintain a knowledge graph under `graphify-out/`, including architectural relationships, communities, and cross-file dependencies.

Graphify complements the Rails, Ruby, and TDD skills. Use it to understand the existing codebase before making changes.

### Rules

1. For codebase questions and implementation tasks, first use Graphify when `graphify-out/graph.json` exists.
2. Run `graphify query "<question>"` to identify relevant components, files, and relationships.
3. Use `graphify path "<A>" "<B>"` to investigate relationships between specific components.
4. Use `graphify explain "<concept>"` to investigate a focused concept or subsystem.
5. If `graphify-out/wiki/index.md` exists, use it for broad codebase navigation instead of immediately browsing the source tree manually.
6. Read `graphify-out/GRAPH_REPORT.md` only for broad architecture reviews or when targeted Graphify results are insufficient.
7. Treat Graphify as a navigation and analysis aid, not as the definitive source of truth. Verify important behavior, interfaces, business rules, and dependencies against the actual source code and tests.
8. Dirty or incrementally updated files under `graphify-out/` are not a reason to skip Graphify.
9. Skip the normal Graphify investigation only when the task concerns stale or incorrect graph output itself, or the user explicitly asks not to use Graphify.
10. If Graphify is unavailable, the graph does not exist, or its results are insufficient, continue with appropriate source-code exploration tools. Do not block implementation unnecessarily.
11. After modifying application code, run `graphify update .` when the command is available. Do not run it for documentation-only changes unless the documentation affects indexed content or the user requests it.
12. When the user explicitly invokes `/graphify`, consult the installed Graphify skill or instructions before doing anything else.

### Efficient usage

- Prefer targeted queries over reading the entire graph report.
- Use Graphify to identify relevant files, then inspect those files before editing.
- Avoid repeating queries when existing results already answer the question.
- Do not assume a graph relationship proves runtime behavior.
- Report if the graph update fails.

## 4. Clean Code Principles

Write code for the next developer who must understand, debug, and modify it.

- Prefer simple, explicit solutions over clever abstractions.
- Follow established Rails and Ruby conventions unless there is a concrete reason not to.
- Keep methods focused on one responsibility.
- Give classes, methods, variables, and files descriptive names.
- Avoid duplicated business logic.
- Avoid unnecessary indirection, premature generalization, and speculative abstractions.
- Keep controllers, models, views, jobs, services, and frontend code focused on their appropriate responsibilities.
- Extract complex logic when doing so improves readability, testability, or reuse.
- Avoid excessively large classes, long methods, deeply nested conditionals, and boolean-heavy APIs.
- Use guard clauses when they improve clarity.
- Prefer explicit domain concepts over vague names such as `Manager`, `Handler`, or `Processor` without meaningful context.
- Do not add comments that merely repeat what the code says. Explain non-obvious business rules and important trade-offs.
- Remove dead code and obsolete implementation paths when they become unnecessary as part of the task.
- Do not refactor unrelated code simply because it could be improved.
- Do not optimize prematurely. Address demonstrated performance issues or clear inefficiencies.

**The goal is the simplest maintainable solution, not the fewest lines of code.**

## 5. Understand Before Changing

Before implementing a task:

1. Use Graphify to locate relevant components and relationships when available.
2. Inspect the relevant models, controllers, views, jobs, services, JavaScript modules, routes, migrations, and tests.
3. Understand the existing data model and the business rules affected by the change.
4. Look for existing methods, components, and patterns that can be reused.
5. Identify the smallest coherent change that solves the problem.
6. Determine which tests must be added or updated.

Do not assume the application follows a convention merely because it is common in Rails. Verify how the project implements the relevant behavior.

Avoid unnecessary exploration unrelated to the task.

## 6. Rails Architecture

Follow Rails conventions and keep responsibilities clear.

### Models

- Models own persistence-related behavior, validations, associations, and domain behavior that naturally belongs to the model.
- Avoid turning Active Record models into containers for unrelated application workflows.
- Keep callbacks minimal and predictable.
- Do not hide important financial side effects in unexpected callbacks.
- Use database constraints for critical invariants when appropriate, in addition to model validations.

### Controllers

- Keep controllers focused on HTTP concerns, authorization, request handling, and response rendering.
- Avoid placing complex business workflows or calculations directly in controllers.
- Use strong parameters and follow the application's existing authorization conventions.
- Do not expose sensitive financial information to unauthorized users.

### Services and domain logic

- Introduce a service object or another dedicated abstraction when a meaningful workflow cannot be expressed clearly within existing Rails responsibilities.
- Keep service interfaces small and explicit.
- Do not create a service class for every model operation.
- Keep financial calculations and transaction workflows easy to test independently.
- Avoid creating multiple layers of indirection for simple operations.

### Views and partials

- Keep ERB templates focused on presentation.
- Use partials for genuinely reusable or logically independent interface sections.
- Avoid complex business logic, data transformations, and large conditional blocks in templates.
- Do not place application JavaScript inside ERB templates.

### Background jobs

- Use Solid Queue for work that should execute asynchronously or outside the request lifecycle.
- Keep jobs focused on orchestration; move substantial business logic into appropriate application objects.
- Make jobs safe to retry when retries are possible.
- Consider duplicate execution, idempotency, failure handling, and transaction boundaries.
- Do not move simple synchronous operations into background jobs without a clear reason.

## 7. JavaScript and Frontend Organization

**Strict rule: application JavaScript must live in dedicated JavaScript files, never inline in `.html.erb` templates. Do not accumulate feature implementations in `application.js`.**

### File organization

- Place JavaScript in the project's established JavaScript directory, normally `app/javascript/`.
- Organize code by feature or responsibility rather than putting everything in a single global file.
- Use separate modules for independent features, UI interactions, and reusable behavior.
- Keep `application.js` as a small entry point responsible for loading or registering the necessary modules.
- Do not accumulate feature-specific event handlers, DOM manipulation, and business-specific behavior in `application.js`.
- Follow the project's existing module system, bundling configuration, and frontend conventions.
- Do not introduce a new bundler, framework, or module system without a clear need.

An example structure:

    app/javascript/
      application.js
      controllers/
      features/
        expenses/
          form.js
          filters.js
        money_sources/
          form.js
        financial_goals/
          form.js

This is an organizational example, not a requirement to create every directory or file.

### ERB restrictions

Never add inline application scripts such as:

    <script>
      // Feature implementation
    </script>

Do not embed substantial JavaScript in ERB attributes, partials, or HTML strings.

Instead:

1. Create or update the appropriate JavaScript module.
2. Load it through the existing entry point or registration mechanism.
3. Connect it to the page using stable selectors, data attributes, or the project's existing frontend conventions.
4. Keep the ERB template responsible for markup and presentation.

Small declarative HTML attributes are acceptable when they follow established project conventions, but they must not become a way to hide application logic inside templates.

### JavaScript quality

- Keep modules focused on one feature or responsibility.
- Avoid global variables and unnecessary global event handlers.
- Prevent duplicate event registration when pages or partials are loaded more than once.
- Clean up event listeners and subscriptions when their lifecycle requires it.
- Avoid tightly coupling JavaScript to fragile CSS selectors or translated display text.
- Use data attributes when the frontend needs explicit values from Rails.
- Escape or safely render user-provided content. Never inject untrusted content as executable HTML.
- Handle loading, empty, success, and error states when relevant.
- Do not introduce a frontend framework or dependency for a small interaction that can be implemented cleanly with the existing stack.

## 8. PostgreSQL and Data Integrity

Financial data must remain consistent and accurate.

- Use database transactions for operations that must succeed or fail as a unit.
- Add appropriate foreign keys, unique constraints, indexes, and database constraints.
- Do not rely exclusively on Rails validations for invariants that must hold at the database level.
- Write explicit migrations that are reversible when practical and consistent with the existing schema.
- Avoid unnecessary database queries and N+1 problems.
- Use eager loading when appropriate.
- Avoid loading large datasets into memory when a database query can perform the operation efficiently.
- Preserve existing data and relationships when changing schemas.
- Do not silently change the meaning of existing records.
- Consider concurrent requests and database-level race conditions when enforcing uniqueness or updating balances.

### Financial precision

- Use decimal-based representations for monetary amounts. Never use floating-point arithmetic for financial calculations.
- Follow the application's existing currency and amount conventions.
- Make rounding behavior explicit when it affects financial results.
- Keep transfers, expenses, income, debt payments, credit advances, and account balances semantically distinct.
- Avoid counting a transfer as income or an expense unless the business rules explicitly require it.
- Ensure operations affecting multiple balances remain consistent if any step fails.
- Consider concurrent operations and duplicate requests when updating financial records.
- Preserve historical transaction accuracy when changing financial rules or calculations.

Never invent or silently modify financial business rules. Inspect the existing implementation and tests first. If the intended behavior is unclear and materially affects financial correctness, ask for clarification.

## 9. Action Cable, Solid Queue, and Solid Cache

### Action Cable

- Use Action Cable for real-time communication where the feature requires it.
- Keep channel responsibilities focused.
- Authenticate connections and authorize subscriptions appropriately.
- Do not broadcast sensitive financial information to unauthorized users.
- Avoid unnecessary broadcasts and expensive synchronous work during message delivery.
- Ensure broadcasts target the appropriate user or authorized audience.

### Solid Queue

- Use background jobs for appropriate asynchronous work.
- Ensure retries do not create duplicate expenses, income entries, transfers, or other financial records.
- Handle failures explicitly where the workflow requires recovery or user feedback.
- Make job execution observable enough to diagnose failures without logging sensitive financial data.
- Follow the project's existing queue and retry configuration.

### Solid Cache

- Cache only when there is a clear performance or workload benefit.
- Use predictable cache keys and appropriate expiration or invalidation strategies.
- Ensure cached financial data cannot leak across users.
- Account for stale data when balances, transactions, or other underlying records change.
- Do not introduce caching as a substitute for fixing an inefficient query or incorrect data model.

Use Rails 8 and the installed versions of these components as the source of truth. Verify available APIs and configuration in the project before relying on features from other versions.

## 10. Testing and TDD

The project uses **Minitest**, not RSpec.

Follow the project's TDD skill and existing Minitest conventions.

### Mandatory rules

- Never introduce RSpec or convert existing tests to RSpec.
- Use the existing Minitest test structure, helpers, fixtures, assertions, and naming conventions.
- Before writing tests, inspect similar tests in the project and follow their patterns.
- For behavioral changes and bug fixes, write or update a test that demonstrates the expected behavior before implementing the solution.
- Run the relevant test and verify that it fails for the intended reason when practical.
- Implement the smallest change that satisfies the test.
- Run the relevant tests again and verify the results.
- Run additional regression tests when the change affects related behavior.
- Test observable behavior and business rules rather than implementation details unnecessarily.
- Do not modify test configuration or introduce another testing framework without explicit justification.

### Minitest conventions

- Use the test type appropriate to the behavior being tested, following existing project conventions.
- Use `test "descriptive behavior" do` for test names when consistent with the existing suite.
- Use native Minitest assertions such as `assert`, `assert_equal`, `assert_difference`, `assert_no_difference`, `assert_nil`, `assert_raises`, and `refute` where appropriate.
- Use Rails test helpers and fixtures when they are already part of the project's testing approach.
- Do not introduce factories, custom helpers, or test abstractions without a clear benefit.
- Keep tests focused, deterministic, and independent whenever practical.
- Avoid unnecessary database setup and expensive operations in tests.

### Test coverage priorities

Prioritize tests for:

- Monetary calculations, decimal precision, and rounding.
- Expenses, income, transfers, and balance changes.
- Credit cards, revolving credit, loans, and debt payments.
- Validations, database constraints, and transaction rollback.
- Authorization and user data isolation.
- Background job retries and duplicate execution.
- Cache invalidation when financial data changes.
- Action Cable authorization and message delivery.
- JavaScript interactions that affect financial workflows.
- Regression scenarios for previously reported bugs.

### Running tests

- Follow the project's existing test commands and configuration.
- Run the narrowest relevant test first, then expand coverage as needed.
- Do not assume tests passed unless they were actually executed and passed.
- If a test cannot be run, explain why and report what remains unverified.
- Never hide failures or change assertions merely to make a test pass without verifying the expected behavior.

The TDD skill defines the detailed workflow; these rules establish Minitest as the project's required testing framework.

## 11. Security and Privacy

- Follow Rails security best practices.
- Protect user financial information and enforce authorization at the appropriate boundaries.
- Never expose secrets, credentials, tokens, or sensitive financial data in logs, broadcasts, or error messages.
- Avoid logging complete financial conversations or user-submitted content unless explicitly necessary and appropriately protected.
- Validate and safely process uploaded files and external input.
- Do not trust client-provided user IDs, amounts, ownership information, or permissions.
- Use parameterized database queries and safe output rendering.
- Keep sensitive configuration in environment variables or the project's approved secrets mechanism.

## 12. Dependencies and Configuration

- Prefer existing Rails and Ruby capabilities over adding dependencies.
- Add a gem or JavaScript package only when its benefits justify the additional maintenance and security surface.
- Do not upgrade Rails, Ruby, PostgreSQL, or other infrastructure dependencies as part of an unrelated task.
- Do not hardcode secrets, environment-specific values, or credentials.
- Follow existing environment configuration and deployment conventions.
- Do not introduce new infrastructure when existing Rails 8 components can meet the requirement.

## 13. Scope Control

- Implement only what the task requires.
- Preserve existing behavior unless the task explicitly changes it.
- Avoid unrelated refactoring, renaming, formatting changes, and dependency upgrades.
- Do not create speculative abstractions for hypothetical future requirements.
- If the requested solution requires a significant architectural change, explain why before expanding the scope.
- If requirements are ambiguous and the ambiguity could affect financial correctness or data integrity, ask for clarification rather than inventing business rules.
- Prefer small, reviewable changes that are easy to test and maintain.

## 14. Completion Checklist

Before declaring a task complete, verify:

- [ ] Relevant Graphify investigation was performed when applicable.
- [ ] Relevant Rails, Ruby, and TDD skills were followed.
- [ ] The implementation follows existing project conventions.
- [ ] The code is focused, readable, and maintainable.
- [ ] No application JavaScript was added inline to ERB templates.
- [ ] Feature-specific JavaScript lives in dedicated modules rather than being accumulated in `application.js`.
- [ ] Financial rules and data integrity are preserved.
- [ ] Relevant Minitest tests were added or updated.
- [ ] Relevant tests were executed, and their actual results are known.
- [ ] Database migrations, background jobs, and cache invalidation were considered where applicable.
- [ ] No unrelated changes or unnecessary dependencies were introduced.
- [ ] Graphify was updated after application code changes when available.

## 15. Final Response

When reporting completed work, summarize:

1. What changed and why.
2. Important implementation or architectural decisions.
3. Tests executed and their actual results.
4. Any known limitations or follow-up work.

Keep the report concise and useful. Never claim completion, correctness, or test success without evidence.