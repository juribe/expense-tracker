---
name: rails-standards
version: 0.2.0
description: Ruby on Rails conventions for models, controllers, views, concerns, services, authorization, and database. Use when writing or reviewing Rails code to ensure consistency with project standards.
---

# Rails Standards

## When to Use This Skill
Use this skill when writing or reviewing Ruby on Rails code. It assumes the `ruby-standards` skill is already in effect. When this document and a project's `README.md` disagree, the README wins.

## Guiding Principles

1. **Trust the framework.** Don't re-implement what `ActiveRecord` already does, don't validate at boundaries Rails already guards, don't re-test built-in behaviour.
2. **Skinny controllers, fat models, no logic in views.**
3. **Eager-load by default.** N+1 is a regression, not a footnote.
4. **One responsibility per layer.** If a controller is reaching into multiple models to coordinate work, that's a service object.

## Top-of-File Comments

The default from `ruby-standards` still holds — only add a file-level comment when the file's purpose or public API isn't obvious from its name. When you do add one, follow the Rails-layer-specific structure below.

### Models and concerns
- Name
- 10-word summary
- Important associations (especially polymorphic, scoped, or non-obvious ones)
- Key methods
- One short usage example

```ruby
# Order
# Customer-facing order; soft-deleted via Discardable.
#
# Associations: belongs_to :customer, has_many :line_items (dependent: :destroy)
# Methods: total, ready_to_ship?, fulfil!
#
# Example: Order.find(id).fulfil!
class Order < ApplicationRecord
  # ...
end
```

### Controllers
- Name
- Routes the controller serves (or "RESTful for Order")
- Behaviour summary — auth, special filters, anything non-obvious

```ruby
# OrdersController
# RESTful for Order, plus POST /orders/:id/fulfil.
# Requires signed-in member; admin-only on destroy.
class OrdersController < ApplicationController
  # ...
end
```

### Helpers
- Name
- Public methods
- One short usage example

```ruby
# OrdersHelper
# Methods: order_status_badge, formatted_total
#
# Example: order_status_badge(order) # => <span class="badge ...">Paid</span>
module OrdersHelper
  # ...
end
```

## Models

### File layout
1. `include` / `extend`
2. `attr_readonly`, `attr_accessor` declarations
3. Constants
4. Associations (`belongs_to`, `has_many`, `accepts_nested_attributes_for`)
5. Validations
6. Callbacks (`after_initialize`, `before_validation`, `after_create`, etc.)
7. Class methods (`self.foo`)
8. Public instance methods
9. `private`

### Associations
- **`dependent:` is required** on every `has_many` / `has_one`. Be explicit: `:destroy`, `:nullify`, or `:restrict_with_exception`.
- Use `inverse_of` when Rails can't infer it (custom `class_name`, polymorphic, scoped associations).

### Validations and callbacks
- Validations are about data shape. Business rules that depend on state belong in a custom validator method, not a one-liner.
- Use callbacks sparingly — they're action at a distance. Anything more than "derive this column from these two columns" probably wants a service object.
- **No I/O in callbacks** — sending email, calling APIs, geocoding all belong in a background job, not a callback.

### Scopes
Prefer scopes over class methods that return relations:

```ruby
scope :active,   -> { where(discarded_at: nil) }
scope :recent,   -> { order(created_at: :desc) }
scope :for_user, ->(user) { where(owner: user) }
```

### Queries
- **Eager-load** everything an index will render: `Order.includes(:customer, :line_items)`.
- Use `pluck` when you only need columns; don't instantiate records you'll throw away.
- Use `find_each` for any iteration over a large relation.

## Controllers

Controllers are thin. They authenticate, authorize, parse params, hand off to the model, and render.

### Action order
`index → show → new → edit → create → update → destroy → custom actions → private`.

### Private method order
1. **Callback methods** (used in `before_action` etc.)
2. **Finder methods** (`set_<resource>`)
3. **Helper methods** (`save_and_respond`, etc.)
4. **Strong-parameter methods** (`<resource>_params`)

### Strong parameters
- Use `params.expect(...)` (Rails 8+). Do not fall back to `require`/`permit` unless `expect` cannot express the shape.
- Extract anything complex into a dedicated method.
- One params method per resource.

```ruby
private

def set_order
  @order = Order.find(params.expect(:id))
end

def order_params
  params.expect(order: [:reference, :notes,
                        { line_items_attributes: [[:id, :sku, :quantity, :_destroy]] }])
end
```

### Response patterns
- Pair invalid `create`/`update` renders with `status: :unprocessable_entity`.
- When supporting Turbo, render both `format.turbo_stream` and `format.html` explicitly — don't rely on implicit rendering.
- **Never use `reload` in a controller to "fix" a timing issue.** That's a signal that the model or the test is wrong.

```ruby
def create
  @order = Order.new(order_params)
  authorize @order

  if @order.save
    redirect_to @order, notice: "Order created."
  else
    render :new, status: :unprocessable_entity
  end
end
```

## Views

- Use the project's chosen markup and CSS — defer to the README for specifics.
- **No business logic in views.** Extract to a helper or a presenter method on the model.
- Styling must work in both light and dark modes.
- Prefer partials for any markup repeated more than once.
- Prefer view helpers for any non-trivial conditional rendering.

## Concerns and Service Objects

- A **concern** is for behaviour that genuinely belongs on the model and is reused across models (soft delete, slugging, audit fields). It should not be a junk drawer.
- A **service object** is for a multi-step operation that doesn't belong to a single model (a discovery process that touches several records, a complex calculation with multiple inputs, an integration with a third party). Follow the service-style conventions from the `ruby-standards` skill.
- Don't open `ApplicationRecord` to add a method used by a single model — put it on the model itself.

## Authorization, Background Work, Real-Time

- **Authorization** lives in policy objects (e.g., Pundit policies under `app/policies/`). Authorize in the controller; don't sprinkle role checks through the view.
- **Background jobs** are for slow or external work — sending email, calling APIs, geocoding. Keep the job thin: read inputs, call a service object, handle retries.
- **ActionCable / Turbo Streams** broadcasts belong in the model callback or service, not the controller — the controller already returned.

## Database

- Migrations are reversible. Use `change`; only drop to `up`/`down` when irreversible.
- Add a NOT NULL constraint and an index every time you add a foreign key.
- Default booleans to `false`, not `nil`.
- Never reach into another model's table directly — go through the model.

## Related Skills
- Use `ruby-standards` for language-level conventions.
- Use `rspec-standards` for testing patterns.
- Use `tdd-workflow` for the overall development process.
- Use `project-context` for project-specific conventions and stack versions.
