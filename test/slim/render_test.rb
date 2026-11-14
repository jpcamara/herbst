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
    def classes = ["a", nil, ["b", ""]]
    def attribute_value = "helper"
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

  it "renders data hash values, Array classes and true from any code like Slim" do
    source = <<~SLIM
      p data={ a: missing, b: admin?, c: user?, d: role }
      p class=classes
      p.x class=classes
      p title=user? = attribute_value
    SLIM

    expected = Slim::Template.new(format: :html) { source }.render(Scope.new)
    actual = Scope.new.instance_eval(Herb::Engine.new(Herbst::Slim.to_erb(source), escape: true).src)

    assert_equal %(<p data-a="" data-b="false" data-c data-d="a"></p><p class="a b"></p><p class="x a b"></p><p title>helper</p>), expected
    assert_equal expected.gsub(/(data-c|title)(?==|>| )/, '\\1=""'), actual.force_encoding(Encoding::UTF_8).delete("\n").squeeze(" ").gsub(/\s+>/, ">")
  end

  it "renders the attributes of a tag with a splat like Slim" do
    splats = [
      { disabled: true, hidden: false, title: nil }, { title: "", tabindex: 1, role: :button }, { title: %(a"b<c&'), foo_bar: 1 },
      { "aria-label" => "x" }, { data: { id: 1, user_name: "x", c: { e: 1 }, a: nil, b: false, t: true, ids: [1, 2] } },
      { data: "x" }, { aria: { label: "x", hidden: true } }, { class: ["a", nil, "b"] }, { class: :a }, { id: ["a", "b"] },
      { style: { color: "red" } }, { "class" => "s", class: "t" }, {}
    ]
    sources = [%(p *opts), %(a.x#i(class=extra title="t \#{name}" disabled *opts)), %(a href=url data=opts[:data] *opts.except(:data))]

    sources.product(splats).each do |source, opts|
      code = Herbst::Slim.to_erb(source)[/<%== (.*) %>/, 1]
      scope = Scope.new.instance_eval { binding }.tap { |binding| binding.local_variable_set(:opts, opts) }
      begin
        expected = Slim::Template.new(format: :xhtml) { source }.render(Scope.new, opts: opts)
      rescue RuntimeError => e
        assert_raises(RuntimeError, e.message) { scope.eval(code) }
        next
      end
      attributes = scope.eval(code)

      assert_equal expected, %(#{expected[/\A<\w+/]}#{" " unless attributes.empty?}#{attributes}>#{expected[%r{</\w+>\z}]}), "#{source} with #{opts}"
    end
  end

  it "raises for a duplicate attribute of a tag with a splat like Slim" do
    code = Herbst::Slim.to_erb(%(p title="a" *opts))[/<%== (.*) %>/, 1]
    scope = Scope.new.instance_eval { binding }.tap { |binding| binding.local_variable_set(:opts, { title: "b" }) }

    assert_raises(RuntimeError, "Multiple title attributes specified") { scope.eval(code) }
  end

  it "merges the class of a splat that is a Hash literal like Slim" do
    source = <<~SLIM
      .cute *{class: "nice"} A
      a.x class=role *{class: ["y"], title: name} B
    SLIM

    expected = Slim::Template.new(format: :html) { source }.render(Scope.new)
    actual = Scope.new.instance_eval(Herb::Engine.new(Herbst::Slim.to_erb(source), escape: true).src)

    assert_equal %(<div class="cute nice">A</div><a class="x a y" title="&lt;World&gt;">B</a>), expected
    assert_equal expected, actual.force_encoding(Encoding::UTF_8).delete("\n")
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
