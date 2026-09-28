# frozen_string_literal: true

require "test_helper"

module Whatsapp
  class GarbageFilterTest < ActiveSupport::TestCase
    test "rejects keyboard mash" do
      assert GarbageFilter.garbage?("sdksmdksmnkd skd kjs kdj skd")
      assert GarbageFilter.garbage?("asdfghjkl")
    end

    test "rejects repeated tokens and very low diversity" do
      assert GarbageFilter.garbage?("hola hola hola")
      assert GarbageFilter.garbage?("aa bb aa bb aa bb aa")
    end

    test "rejects vowel-less long words" do
      assert GarbageFilter.garbage?("skjdfklsd")
    end

    test "accepts expense messages without digits" do
      refute GarbageFilter.garbage?("almuerzo con Juan")
      refute GarbageFilter.garbage?("pagué el mercado en Éxito")
    end

    test "accepts clarification answers" do
      refute GarbageFilter.garbage?("nequi")
      refute GarbageFilter.garbage?("50 mil")
      refute GarbageFilter.garbage?("con davibank")
      refute GarbageFilter.garbage?("transporte")
      refute GarbageFilter.garbage?("ayer")
      refute GarbageFilter.garbage?("cancelar")
    end

    test "accepts short coherent words" do
      refute GarbageFilter.garbage?("hola")
      refute GarbageFilter.garbage?("ok")
    end

    test "handles blank text" do
      refute GarbageFilter.garbage?(nil)
      refute GarbageFilter.garbage?("")
      refute GarbageFilter.garbage?("   ")
    end
  end
end
