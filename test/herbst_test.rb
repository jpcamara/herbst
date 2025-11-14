# frozen_string_literal: true

require "test_helper"

class TestHerbst < Minitest::Spec
  it "that it has a version number" do
    refute_nil ::Herbst::VERSION
  end
end
