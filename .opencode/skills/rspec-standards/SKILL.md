---
name: rspec-standards
version: 0.2.0
description: RSpec conventions for structure, style, descriptions, spec boundaries (model/controller/request/system), and factories. Use when writing or reviewing RSpec tests.
---

# RSpec Standards

## When to Use This Skill
Use this skill when writing or reviewing RSpec tests. It assumes the `ruby-standards` and `rails-standards` skills are already in effect.

## Guiding Principles

1. **Tests come before implementation.** A failing test names the behaviour; the implementation just satisfies it.
2. **One responsibility per spec type.** Don't duplicate model coverage in controller specs or controller coverage in system specs.
3. **Trust the framework.** Don't re-test Rails' built-in validations or association mechanics.
4. **Descriptions are sentences about behaviour**, not narration of test mechanics.
5. **Don't stub the system under test.** Stubbing the thing you're testing tests the stub, not the code.

## File Structure

- File name: `spec/<area>/<thing>_spec.rb`.
- Top of file: `RSpec.describe Thing, type: :model` — always pass the `type:`.
- Do **not** add `require 'rails_helper'` — it's wired by `.rspec`.
- Declare `subject(:meaningful_name)` at the top of the outermost `describe`. Use `create` for the subject in model specs unless you specifically need `build`.
- Use `let` (not nested `subject`) for per-context data, declared close to where it's used.
- Never share state across examples via `@ivars` set in `before(:all)` — use `let` or a per-example `before`.

## Spec Boundaries

Each spec type owns a specific concern. Don't duplicate.

| Spec type   | Focus                                                                                              | Don't put here                                                            |
|-------------|----------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------|
| Model       | Validations, associations, scopes, business logic, state transitions                               | Controller/request behaviour; re-testing Rails                            |
| Controller  | Response status/format, template, instance vars, strong params, delegation to models               | Business logic; end-to-end flows; deep view assertions; authorization internals |
| Request     | Multi-step journeys, redirects + final content, cross-component side effects, auth flows           | Exhaustive invalid cases; individual method behaviour                     |
| System      | Browser-level workflows that exercise JavaScript; user-visible behaviour a user can see and trigger | Anything a controller/request spec already covers                         |

## Model Spec Template

```ruby
RSpec.describe Order, type: :model do
  subject(:order) { create(:order) }

  describe 'factory' do
    it 'is valid' do
      expect(order).to be_valid
    end
  end

  describe 'associations' do
    it 'destroys line items when destroyed' do
      create(:line_item, order: order)
      expect { order.destroy }.to change(LineItem, :count).by(-1)
    end
  end

  describe 'validations' do
    it 'is not valid without a reference' do
      order.reference = nil
      expect(order).to_not be_valid
      expect(order.errors[:reference]).to be_present
    end
  end

  describe '#total' do
    it 'sums line item amounts' do
      create(:line_item, order: order, amount: 5)
      create(:line_item, order: order, amount: 7)
      expect(order.total).to eq(12)
    end
  end

  describe '.recent' do
    it 'orders by most recent first' do
      older = create(:order, created_at: 2.days.ago)
      newer = create(:order, created_at: 1.day.ago)
      expect(Order.recent).to eq([newer, older])
    end
  end
end
```

### Model spec ordering
1. `describe 'factory'` — always first.
2. `describe 'associations'` — test behaviour (cascading deletes, counter caches), not just presence.
3. `describe 'validations'` — presence, uniqueness, format, custom rules.
4. `describe '#instance_method'` / `describe '.class_method'` — one block per method.

## Style

- **`expect().to`** syntax only — never `should`.
- **`to_not be_valid`**, never `to be_invalid`.
- Don't assert on exact error messages unless the message is the contract; assert `errors[:field]` is present.
- Use `change` for side effects:

  ```ruby
  expect { do_thing }
    .to change(Order, :count).by(1)
    .and change(AuditEntry, :count).by(1)
  ```

- Prefer specific matchers:
  - `be_present`, `be_blank`
  - `be_valid`, `to_not be_valid`
  - `be_successful`, `be_redirect`
  - `match_array` when order doesn't matter, `eq` when it does
  - `include` for partial collection matches

## Descriptions

- Direct, present tense, no `should`:
  - `"is valid"` — not `"should be valid"`.
  - `"is not valid without a name"` — not `"validates presence of name"`.
  - `"creates a user"` — not `"should create a valid user object"`.
- `context` describes a scenario, starts with "when" or "with":
  - `context "when the user is an admin"`
  - `context "with no line items"`

## Controller Specs

Controller specs cover status, template, instance vars, and strong-parameter behaviour. Nothing else.

```ruby
RSpec.describe OrdersController, type: :controller do
  signed_in_member

  describe "PUT #update" do
    let!(:order) { create(:order, owner: signed_in_member) }

    context "when reference is updated" do
      it "persists the new reference" do
        put :update, params: { id: order.id, order: { reference: "ABC-123" } }
        expect(order.reload.reference).to eq("ABC-123")
        expect(response).to redirect_to(order)
      end
    end
  end
end
```

## Request Specs

Request specs cover **journeys**: navigate → action → redirect → content verification. Use `follow_redirect!` and assert on the final page. The [Spec Boundaries](#spec-boundaries) table covers what doesn't belong here.

## System Specs

- Any spec involving Stimulus, Turbo, ActionCable, or any JS-driven interaction **must** be tagged `:js`.
- Use waiting matchers (`have_content`, `have_selector`) — never `sleep`.
- System specs are for behaviour a user can see and trigger. Don't use them to cover ground a controller or request spec already covers.

## Test Data

- Use FactoryBot factories in `spec/factories/`; use Faker for dynamic values.
- Every model gets a factory; every factory is validated by a `describe 'factory'` block.
- Use **traits** for variants — don't make a second factory.
- Authentication helpers live in `spec/support/`; use the project's `signed_in_<role>` helper instead of stubbing `current_user`.

## Quality Loop

1. Write the spec. Watch it fail for the right reason.
2. Write the minimum implementation to make it pass.
3. Refactor.
4. Run the full file, then the directory, then the suite.
5. Before committing, strip any `focus: true` / `:focus` markers — they silently skip the rest of the suite.

### When tests fail
- **First failure:** read the error, attempt a fix, re-run.
- **Second failure:** **stop**. Present the error and ask the user before another attempt. Repeated failures usually mean a misunderstood problem, not a typo.

## Related Skills
- Use `ruby-standards` for language-level conventions.
- Use `rails-standards` for Rails-specific conventions.
- Use `tdd-workflow` for the overall development process.
- Use `system-test-patterns` for browser testing specifics and flake debugging.
