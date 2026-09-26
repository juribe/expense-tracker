---
name: ruby-standards
version: 0.3.0
description: Ruby language conventions covering naming, methods, classes, error handling, and service-style objects. Use when writing or reviewing plain Ruby code — language-level guidance independent of Rails.
---

# Ruby Standards

## When to Use This Skill
Use this skill when writing or reviewing plain Ruby code. It covers language-level conventions only. Framework concerns belong in the `rails-standards` and `rspec-standards` skills.

## Guiding Principles

1. **Model the domain with objects.** Ruby is an object-oriented language — use it. Behaviour belongs on the object that owns the data, not in procedural helpers, free-floating modules of class methods, or `Utils`-style grab-bags. Reach for a class before reaching for a hash, a `case` statement, or a script.
2. **Self-documenting beats commented.** Names should make comments redundant.
3. **One responsibility per method.** If a method does two things, it probably wants to be two methods.
4. **Make the success path the main story.** Use guard clauses; reserve the body for what actually happens.
5. **Calm tone.** Code, comments, commit messages — descriptive, not exclamatory.
6. **Don't build for hypotheticals.** No abstractions for a future caller that doesn't exist.

## Naming

- **Methods are verbs:** `calculate_total`, `send_invitation`, `geocode!`.
- **Variables are nouns:** `invoice`, `recipient`, `coordinates`.
- **Predicate methods end with `?`:** `active?`, `expired?`, `owned_by?(user)`.
- **Mutating or raising methods end with `!`:** `save!`, `discard!`.
- **Be descriptive, not clever:** `calculate_total_with_tax`, not `calc_tt`.
- **Constants are SCREAMING_SNAKE_CASE** and live at the top of the class.

```ruby
class Order
  MAX_LINE_ITEMS = 50

  def ready_to_ship?
    paid? && line_items.any? && shipping_address.present?
  end
end
```

## Comments

The default is **no comments**. Add one only when the *why* is non-obvious — a hidden constraint, a subtle invariant, a workaround for an external quirk.

### Inline comments
- Allowed only for: non-obvious intent, algorithm rationale, edge-case reasoning, external constraints.
- Keep them ≤ 10 words, present tense, focused on intent (not implementation).
- **Never:**
  - Restate what the code says.
  - Leave commented-out code in place.
  - Add bare TODOs — link an issue or remove.

### Top-of-file comments
Only when the file's purpose or public API is not obvious from its name. Keep to:
- Name
- 10-word summary of purpose
- Key methods and one short example, if useful.

```ruby
# Discardable
# Soft delete via discarded_at; restore by setting _undiscard.
#
# Methods: destroy (soft first, hard if re-called), discarded_by?
module Discardable
  # ...
end
```

## Methods and Flow

- **Keep methods short.** If you can't see the whole method on one screen, extract.
- **Use guard clauses** to reduce nesting:

  ```ruby
  def deliver
    return if recipient.blank?
    return if recipient.unsubscribed?
    return if already_delivered_today?

    transport.send(payload)
  end
  ```

- **Memoize expensive reads** with `@_name ||=`, but only when called more than once per instance.
- **Avoid `unless` with `else`** — invert the condition and use `if`.
- **Prefer `map`, `select`, `reject`, `each_with_object`** over manual loops with accumulators.
- **Don't commit debug output** — `puts`, `pp`, `binding.pry`, `byebug` belong on your branch, not in the repo.

## Object-Oriented Design

Default to OOP. Procedural code is the exception, not the norm.

- **Give behaviour a home.** If you're reaching into a hash to compute something, the hash wants to be an object with a method.
- **Tell, don't ask.** Prefer `invoice.send_to(recipient)` over `Mailer.send(invoice.email, invoice.body)`. Let objects do their own work instead of yanking out their innards.
- **Use polymorphism instead of type-checks.** A `case` on `kind` or repeated `is_a?` checks is a class hierarchy (or a strategy object) trying to escape.
- **Prefer small collaborating objects over one big procedure.** A 100-line method with three concerns is three objects.
- **Composition over inheritance.** Inherit only for genuine *is-a* relationships. For *has-a* / *uses-a*, inject a collaborator.
- **Avoid bare module-of-class-methods.** `Foo.bar(x, y, z)` with no state is usually a class waiting to be instantiated — `Foo.new(x, y).bar` carries its inputs as state and lets you test, swap, and extend it.
- **Hide data; expose behaviour.** Public `attr_accessor` on internal state is a smell — expose intention-revealing methods instead.
- **Value objects for concepts, not primitives.** A `Money`, `DateRange`, or `EmailAddress` beats passing around raw integers and strings.

```ruby
# Procedural — don't
def self.format_address(user)
  parts = [user[:street], user[:city], user[:zip]].compact
  parts.join(', ')
end

# Object-oriented — do
class Address
  def initialize(street:, city:, zip:)
    @street, @city, @zip = street, city, zip
  end

  def to_s = [@street, @city, @zip].compact.join(', ')
end
```

## Classes and Modules

- **Order things consistently inside a class:**
  1. `include` / `extend`
  2. `attr_*` declarations
  3. Constants
  4. Class methods (`self.foo`)
  5. Public instance methods
  6. `private`
- One public entry point per class when possible. If a class has more than ~5 public methods, ask whether it's actually two classes.
- **Initializer takes the inputs**; methods take only the immediately relevant arguments.
- Keep state on the instance; pass collaborators in, don't reach for globals.

## Errors and Edge Cases

- **Only catch what you have a plan for.** A bare `rescue` swallows real bugs.
- **Validate at boundaries** (user input, external APIs). Trust internal callers.
- Raise specific exception classes — `ArgumentError`, custom subclasses — not generic `RuntimeError`.
- Don't return `nil` to signal "didn't work" when the caller can't distinguish that from a legitimate `nil` — raise or return a result object.

## Service-Style Objects

For multi-step operations that don't belong to a single data object:

- One public entry point named for the work (`#perform`, `#build`, `#discover`).
- Return the result, not `self`.
- Push private helpers below.

The class shape from [Classes and Modules](#classes-and-modules) still applies — initializer takes the inputs, methods take only the immediately relevant arguments.

```ruby
class WeeklyReportBuilder
  def initialize(account, week:)
    @account = account
    @week    = week
  end

  def build
    return Report.empty if @account.suspended?

    Report.new(
      totals: aggregate_totals,
      flags:  flagged_items
    )
  end

  private

  def aggregate_totals = # ...
  def flagged_items    = # ...
end
```

## Tooling

- **Run `rubocop` before committing.** Treat lint failures like test failures — fix them, don't push past them.
- **The project's `.rubocop.yml` is authoritative.** Cop enable/disable decisions belong there, not in this skill. If a rule is wrong for the codebase, change the config; if it's wrong for one specific line, the code usually wants to change instead.
- **Use `# rubocop:disable` sparingly,** and only with a trailing comment explaining why the cop is wrong here. Re-enable with `# rubocop:enable` as soon as the exception ends.
- **Don't auto-correct on commit.** Running `rubocop -A` blindly can rewrite intent (e.g., turning a deliberately-long method into something cryptic). Review every autofix.

## Related Skills
- Use `rails-standards` for Rails-specific conventions (models, controllers, views).
- Use `rspec-standards` for testing patterns.
- Use `tdd-workflow` for the overall development process.
