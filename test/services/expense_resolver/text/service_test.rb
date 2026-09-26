require "test_helper"

module ExpenseResolver
  module Text
    class ServiceTest < ActiveSupport::TestCase
      test "clean_description drops trailing motion and meal verbs" do
        assert_equal "Almuerzo", Service.clean_description("almuerzo salí")
        assert_equal "Parqueadero", Service.clean_description("parqueadero salimos")
      end

      test "clean_description drops verb-only fragments to nothing" do
        assert_equal "", Service.clean_description("fui")
        assert_equal "", Service.clean_description("fuimos y pagamos")
      end

      test "clean_description keeps the purchased item" do
        assert_equal "Almuerzo", Service.clean_description("gasté 45.000 en almuerzo")
      end
    end
  end
end
