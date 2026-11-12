# frozen_string_literal: true

require "test_helper"
require "slim"

class Herbst::Slim::RenderTest < Minitest::Spec
  include ConversionHelper

  class Scope
    def title = "Herbst <3"
    def name = "<World>"
    def extra = "y"
    def role = :a
    def url = "/path?a=1&b=2"
    def raw_html = "<em>raw</em>"
    def admin? = false
    def user? = true
    def items = ["one", "<two>"]
    def risky = raise("boom & bust")
    def missing = nil
    def presenter = Struct.new(:sharing_path).new(nil)
  end

  it "renders page.slim like Slim" do
    source = File.read(File.join(SLIM_FIXTURES, "page.slim"))

    expected = Slim::Template.new(format: :html) { source }.render(Scope.new)
    actual = Scope.new.instance_eval(Herb::Engine.new(Herbst::Slim.to_erb(source), escape: true).src)

    assert_equal without_block_whitespace(expected), without_block_whitespace(actual.force_encoding(Encoding::UTF_8))
  end

  it "leaves out nil, false and empty class attributes like Slim" do
    source = <<~'SLIM'
      a href=missing title=admin? data-role=role Link
      p class=missing
      p class=admin?
      p class=[missing, (extra if user?)].compact.join(" ")
      p class=[missing].compact.join(" ")
      p class="#{missing}"
      p class="#{"active" if admin?}"
      p class="#{"active" if user?}"
      p class="#{missing}#{role}"
      p class="#{admin?}"
      p class="#{missing} "
    SLIM

    expected = Slim::Template.new(format: :html) { source }.render(Scope.new)
    actual = Scope.new.instance_eval(Herb::Engine.new(Herbst::Slim.to_erb(source), escape: true).src)

    assert_equal expected, actual.force_encoding(Encoding::UTF_8).delete("\n").gsub(/\s+>/, ">")
  end

  it "leaves out nil from a method with a route helper name, and renders true without a value, like Slim" do
    source = <<~SLIM
      button data-url=presenter.sharing_path Share
      p data-tip=(true if user?) data-off=(true if admin?)
    SLIM

    expected = Slim::Template.new(format: :html) { source }.render(Scope.new)
    actual = Scope.new.instance_eval(Herb::Engine.new(Herbst::Slim.to_erb(source), escape: true).src)

    assert_equal %(<button>Share</button><p data-tip></p>), expected
    assert_equal %(<button>Share</button><p data-tip=""></p>), actual.force_encoding(Encoding::UTF_8).delete("\n").squeeze(" ").gsub(/\s+>/, ">")
  end

  private

  def without_block_whitespace(html)
    parts = html.split(/(<[^>]*>)/)

    parts.each_with_index.map do |part, index|
      next part if part.start_with?("<")

      part = part.sub(/\A\s+/, "") if index.positive? && block_tag?(parts[index - 1])
      block_tag?(parts[index + 1]) ? part.sub(/\s+\z/, "") : part
    end.join
  end

  def block_tag?(tag)
    return false unless tag

    name = tag[%r{\A</?([a-zA-Z][\w-]*)}, 1]
    tag.start_with?("<!DOCTYPE") || (name && !Herb::HTML::Elements::INLINE_ELEMENTS.include?(name.downcase))
  end
end
