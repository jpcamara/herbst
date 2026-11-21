# frozen_string_literal: true

require "test_helper"
require "slim"
require "active_support/core_ext/string/output_safety"

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
  end

  class ValueScope
    attr_reader :values, :value

    def initialize(value)
      @value = value
      @values = value
    end

    def shift_value = values.shift
  end

  class LocalsScope < Scope
    def initialize(**locals)
      super()
      locals.each { |name, value| define_singleton_method(name) { value } }
    end
  end

  it "renders page.slim like Slim" do
    source = File.read(File.join(SLIM_FIXTURES, "page.slim"))

    expected = Slim::Template.new(format: :html) { source }.render(Scope.new)
    actual = Scope.new.instance_eval(Herb::Engine.new(Herbst::Slim.to_erb(source), escape: true).src)

    assert_equal without_block_whitespace(expected), without_block_whitespace(actual.force_encoding(Encoding::UTF_8))
  end

  [nil, false, true, "", "a<b"].each do |value|
    it "renders dynamic attributes like Slim for #{value.inspect}" do
      assert_renders_like_slim("p.a title=value id=value href=@value data-b=value", value)
    end
  end

  it "renders raw dynamic attributes escaped, since Herb escapes all attribute output" do
    source = "p title==value"

    assert_equal %(<p title="a<b"></p>), Slim::Template.new(format: :html) { source }.render(ValueScope.new("a<b"))
    assert_equal %(<p title="a&lt;b"></p>), ValueScope.new("a<b").instance_eval(Herb::Engine.new(Herbst::Slim.to_erb(source), escape: true).src)
  end

  [
    "p class=value", ".a class=value", ".a.b class=value class=value", "p class=value class=\"z\"", "p class=value class=value",
    "p class=\"\#{value}\"", ".a class=\"\#{value}\"", "p class=\"b \#{value}\"", "p class=\"\#{value}\" class=value", "p class=[value, \"c\"]",
    "p class=value id=\"a\"", "p class=nil", ".a class=\"\""
  ].each do |source|
    it "renders `#{source}` like Slim" do
      [nil, false, true, "", "x", "a<b", [], ["a", nil, ""], [["b"], "c"]].each do |value|
        assert_renders_like_slim(source, value)
      end
    end
  end

  it "renders class code that starts like an Array literal but isn't one like Slim" do
    [nil, "x", ["a", nil]].each { |value| assert_renders_like_slim(%(p class=[value, "c"].flatten.compact.join(" ")), value) }
  end

  ["p class=(\"a&b\")", "p class==(\"a&b\")", "p.c class==(\"a&b\")", "p.c class=(\"a&b\")"].each do |source|
    it "renders the static class `#{source}` like Slim" do
      assert_renders_like_slim(source, nil)
    end
  end

  [
    "p data=value", "p aria=value", "p data=value class=value", "p data=value class=[value, nil]", ".a data=value class=value", "p data=value title=value",
    "p aria=value class=value", "p data={a: value}", "p data={a: {b: value}}", "p aria={a: value}", "p data={b: value, a: value}", "p data={b: value} id=\"a\"",
    "p data={a: value} class=[value, nil]", "p data={a: nil}", "p data={a: false}", "p data={a: true}", "p data=value class=\"\#{value}\"", "p data=value class=\"\""
  ].each do |source|
    it "renders `#{source}` like Slim" do
      [nil, false, true, "", "x", "a<b", ["a", nil], { z: 1, a: "<" }, { a_b: { c: nil } }].each do |value|
        assert_renders_like_slim(source, value)
      end
    end
  end

  it "renders raw data hashes like Slim" do
    [{ a: "<b>" }, { a: { b_c: "&" } }, true, nil].each { |value| assert_renders_like_slim("p data==value", value) }
  end

  it "renders static classes next to a data attribute like Slim" do
    [nil, "x", { a: 1 }].each do |value|
      assert_renders_like_slim(%(p data=value class=["a", nil]), value)
      assert_renders_like_slim(%(p data=value class=["a", ""] class=nil), value)
    end
  end

  it "renders a runtime data hash before explicit data attributes, where Slim sorts them together" do
    source = %(p data=value data-b="x")

    assert_equal %(<p data-a="1" data-b="x" data-c="2"></p>), Slim::Template.new(format: :html) { source }.render(ValueScope.new({ a: 1, c: 2 }))
    assert_equal %(<p data-a="1" data-c="2" data-b="x"></p>), ValueScope.new({ a: 1, c: 2 }).instance_eval(Herb::Engine.new(Herbst::Slim.to_erb(source), escape: true).src)
  end

  ["input disabled=value", "input disabled=value type=\"a\"", "button disabled=value checked=value x"].each do |source|
    it "renders `#{source}` like Slim" do
      [nil, false, true, "", "x"].each { |value| assert_renders_like_slim(source, value) }
    end
  end

  it "evaluates attribute code once like Slim" do
    ["p title=values.shift", "p title=shift_value"].each do |source|
      expected = Slim::Template.new(format: :html) { source }.render(ValueScope.new([nil, "b"]))
      actual = ValueScope.new([nil, "b"]).instance_eval(Herb::Engine.new(Herbst::Slim.to_erb(source), escape: true).src)

      assert_equal expected, actual
    end
  end

  it "renders a tag with a splat like Slim" do
    splats = [
      { disabled: true, hidden: false, title: nil }, { title: "", tabindex: 1, role: :button }, { title: %(a"b<c&'), foo_bar: 1 },
      { "aria-label" => "x" }, { data: { id: 1, user_name: "x", c: { e: 1 }, a: nil, b: false, t: true, ids: [1, 2] } },
      { data: "x" }, { aria: { label: "x", hidden: true } }, { class: ["a", nil, "b"] }, { class: :a }, { id: ["a", "b"] },
      { style: { color: "red" } }, { "class" => "s", class: "t" }, { class: "<a&b>" }, { class: "" }, { class: nil }, {}
    ]
    sources = [
      %(p *opts), %(a.x#i(class=extra title="t \#{name}" disabled *opts)), %(a href=url data=opts[:data] *opts.except(:data)),
      %(p(class==raw_html *opts)), %(p(class="a \#{{name}} \#{name}" *opts)), %(p(lang='say "hi" \\ \#{name}' *opts)),
      %(p(class='a&b "q" \\ \#{name}' *opts)), %(p(class=='a&b "q" \#{name}' *opts))
    ]

    sources.product(splats).each { |source, opts| assert_splat_renders_like_slim(source, opts: opts) }
  end

  it "does not escape html_safe values again in a tag with a splat, like Slim in Rails" do
    safe = "a &amp; &quot;b&quot;".html_safe
    unsafe = "c & <d>"
    opts = { title: safe, class: safe, data: { name: safe }, lang: unsafe }

    [%(p *opts), %(p(class="\#{safe} \#{unsafe}" *opts))].each do |source|
      assert_splat_renders_like_slim(source, use_html_safe: true, opts: opts, safe: safe, unsafe: unsafe)
    end
  end

  it "renders an attribute of the tag that a splat repeats twice, where Slim raises" do
    source = %(p title="a" *opts)
    error = assert_raises(RuntimeError) { Slim::Template.new(format: :html) { source }.render(LocalsScope.new(opts: { title: "b" })) }

    assert_equal "Multiple title attributes specified", error.message
    assert_equal %(<p title="a" title="b"></p>), LocalsScope.new(opts: { title: "b" }).instance_eval(Herb::Engine.new(Herbst::Slim.to_erb(source), escape: true).src)
  end

  it "raises for an attribute that the splats of a tag repeat like Slim" do
    source = %(p *a *b)
    scope = LocalsScope.new(a: { title: "a" }, b: { title: "b" })

    expected = assert_raises(RuntimeError) { Slim::Template.new(format: :html) { source }.render(scope) }
    actual = assert_raises(RuntimeError) { scope.instance_eval(Herb::Engine.new(Herbst::Slim.to_erb(source), escape: true).src) }

    assert_equal "Multiple title attributes specified", expected.message
    assert_equal expected.message, actual.message
  end

  private

  def assert_renders_like_slim(source, value)
    expected = Slim::Template.new(format: :html) { source }.render(ValueScope.new(value))
    actual = ValueScope.new(value).instance_eval(Herb::Engine.new(Herbst::Slim.to_erb(source), escape: true).src)

    assert_equal expected, actual.force_encoding(Encoding::UTF_8)
  end

  # Slim sorts all attributes; the converted ERB puts the splats after the other attributes. So the
  # attributes are compared sorted, and Slim's `disabled=""` counts as a bare `disabled`. Slim raises
  # when a splat repeats an attribute written on the tag; the converted ERB renders it twice instead.
  def assert_splat_renders_like_slim(source, use_html_safe: false, **locals)
    expected = rendered_or_raised { Slim::Template.new(format: :html, use_html_safe: use_html_safe) { source }.render(LocalsScope.new(**locals)) }
    actual = rendered_or_raised { LocalsScope.new(**locals).instance_eval(Herb::Engine.new(Herbst::Slim.to_erb(source), escape: true).src) }
    message = "#{source} with #{locals}"

    if expected.is_a?(RuntimeError) && actual.is_a?(RuntimeError)
      assert_equal expected.message, actual.message, message
    elsif expected.is_a?(RuntimeError)
      repeated = expected.message[/\AMultiple (\S+) attributes specified\z/, 1].to_s
      assert_equal 2, actual.to_s.scan(/ #{Regexp.escape(repeated)}[ =>]/).size, message
    else
      assert_equal sorted_attributes(expected.to_s), sorted_attributes(actual.to_s), message
    end
  end

  def rendered_or_raised
    yield.force_encoding(Encoding::UTF_8)
  rescue RuntimeError => e
    e
  end

  def sorted_attributes(html)
    attribute = /[^\s=>]+(?:="[^"]*")?/

    html.sub(/\A<(\w+)((?:\s+#{attribute})*)\s*>/) do
      name, attributes = Regexp.last_match&.captures
      "<#{name}#{attributes.to_s.scan(attribute).map { |item| " #{item.delete_suffix(%(=""))}" }.sort.join}>"
    end
  end

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
