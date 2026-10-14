# frozen_string_literal: true

require "test_helper"

class StatementFormatMappingTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Statement Mapping", email: "statement_mapping@example.com", password: "password123")
  end

  test "fingerprint is stable across whitespace and case" do
    assert_equal StatementFormatMapping.fingerprint([ "Davibank", "Transacciones del periodo" ]),
                 StatementFormatMapping.fingerprint([ "davibank", "  transacciones   del periodo " ])
  end

  test "record! persists a learned layout" do
    mapping = StatementFormatMapping.record!(
      user: @user,
      anchors: [ "Davibank" ],
      sections: { "expenses" => [ "Transacciones del periodo facturado" ] },
      row: { "fields" => [ { "token" => "date" }, { "token" => "amount" } ] },
      bank: "Davibank",
      source: "ai"
    )

    assert mapping.persisted?
    assert_equal "Davibank", mapping.bank
    assert_equal [ "Davibank" ], mapping.anchors
    assert_equal [ "Transacciones del periodo facturado" ], mapping.sections["expenses"]
    assert_equal true, mapping.skip_income
  end

  test "record! is idempotent by fingerprint" do
    first = StatementFormatMapping.record!(user: @user, anchors: [ "Davibank" ],
                                           sections: { "expenses" => [ "A" ] }, row: { "fields" => [] })
    second = StatementFormatMapping.record!(user: @user, anchors: [ "Davibank" ],
                                            sections: { "expenses" => [ "B" ] }, row: { "fields" => [] })

    assert_equal first.id, second.id
    assert_equal 1, StatementFormatMapping.for_user(@user).count
    assert_equal [ "B" ], second.reload.sections["expenses"]
  end

  test "lookup returns the mapping whose anchors all appear in the text" do
    StatementFormatMapping.record!(user: @user, anchors: [ "Davibank pertenece a Davivienda" ],
                                   sections: {}, row: {})

    mapping = StatementFormatMapping.lookup(user: @user, text: "header\nDavibank pertenece a Davivienda Group S.A.\nrows")

    assert_not_nil mapping
  end

  test "lookup prefers the most specific mapping" do
    generic = StatementFormatMapping.record!(user: @user, anchors: [ "Davibank" ], sections: {}, row: {})
    specific = StatementFormatMapping.record!(user: @user, anchors: [ "Davibank", "Transacciones del periodo facturado" ],
                                              sections: {}, row: {})

    mapping = StatementFormatMapping.lookup(user: @user, text: "Davibank\nTransacciones del periodo facturado\nx")

    assert_equal specific.id, mapping.id
    assert_not_equal generic.id, mapping.id
  end

  test "lookup returns nil when anchors do not match" do
    StatementFormatMapping.record!(user: @user, anchors: [ "Davibank" ], sections: {}, row: {})

    assert_nil StatementFormatMapping.lookup(user: @user, text: "Bancolombia extracto")
  end

  test "lookup is scoped to the user" do
    other = User.create!(name: "Other", email: "statement_mapping_other@example.com", password: "password123")
    StatementFormatMapping.record!(user: other, anchors: [ "Davibank" ], sections: {}, row: {})

    assert_nil StatementFormatMapping.lookup(user: @user, text: "Davibank")
  end

  test "record! stores the summary selectors and stamps the current recipe version" do
    summary = { "total_due" => { "label" => "= Pago total", "format" => "amount" } }

    mapping = StatementFormatMapping.record!(
      user: @user, anchors: [ "Davibank" ], sections: {}, row: {}, summary: summary
    )

    assert_equal summary, mapping.summary_spec
    assert_equal StatementFormatMapping::CURRENT_RECIPE_VERSION, mapping.recipe_version
  end

  test "lookup ignores mappings stored by an older recipe version" do
    StatementFormatMapping.record!(user: @user, anchors: [ "Davibank" ], sections: {}, row: {},
                                   recipe_version: StatementFormatMapping::CURRENT_RECIPE_VERSION - 1)

    assert_nil StatementFormatMapping.lookup(user: @user, text: "Davibank extracto")
  end

  test "lookup finds mappings stored by the current recipe version" do
    mapping = StatementFormatMapping.record!(user: @user, anchors: [ "Davibank" ], sections: {}, row: {})

    assert_equal mapping.id, StatementFormatMapping.lookup(user: @user, text: "Davibank extracto").id
  end

  test "validates source inclusion" do
    mapping = StatementFormatMapping.new(user: @user, fingerprint: "x", source: "bogus")

    assert_not mapping.valid?
    assert mapping.errors[:source].any?
  end
end
