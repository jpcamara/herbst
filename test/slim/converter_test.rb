# frozen_string_literal: true

require "test_helper"

class Herbst::Slim::ConverterTest < Minitest::Spec
  include ConversionHelper

  it "converts tags with text" do
    assert_equal "<p>Hello</p>", slim_to_erb("p Hello")
  end

  it "converts shortcuts to a div with class and id" do
    assert_equal %(<div class="a b" id="main"></div>), slim_to_erb("#main.a.b")
  end

  it "only adds whitespace next to block-level elements" do
    assert_equal "<ul>\n  <li>One</li>\n  <li>Two</li>\n</ul>", slim_to_erb("ul\n  li One\n  li Two")
    assert_equal "<p><span>a</span><span>b</span></p>", slim_to_erb("p\n  span a\n  span b")
  end

  it "keeps the whitespace markers" do
    assert_equal "<p><span>a</span> <span>b</span></p>", slim_to_erb("p\n  span> a\n  span b")
    assert_equal "<p>a b</p>", slim_to_erb("p\n  ' a\n  | b")
  end

  it "converts escaped and unescaped output" do
    assert_equal "<%= a %><%== b %>", slim_to_erb("= a\n== b")
    assert_equal "<p><%= a %></p>", slim_to_erb("p = a")
  end

  it "converts interpolation" do
    assert_equal "<p>Hi <%= name %>, <%== raw %>!</p>", slim_to_erb("p Hi \#{name}, \#{{raw}}!")
  end

  it "converts if / elsif / else" do
    slim = "- if a\n  p A\n- elsif b\n  p B\n- else\n  p C"
    assert_equal "<% if a %>\n  <p>A</p>\n<% elsif b %>\n  <p>B</p>\n<% else %>\n  <p>C</p>\n<% end %>", slim_to_erb(slim)
  end

  it "converts case with indented when" do
    assert_equal "<% case x %><% when 1 %>one<% else %>other<% end %>", slim_to_erb("- case x\n  - when 1\n    | one\n  - else\n    | other")
  end

  it "closes block statements without a body, as Slim does" do
    assert_equal "<% if a then b else c %><% end %>", slim_to_erb("- if a then b else c")
  end

  it "moves trailing Ruby comments into ERB comments" do
    assert_equal "<%# note %><% x = 1 %><% if x %>\n  <p>a</p>\n<% end %>", slim_to_erb("- x = 1 # note\n- if x\n  p a")
    assert_equal "<p><%# note %><%= x %></p>", slim_to_erb("p = x # note")
    assert_equal %(<% x = "a # b" %>), slim_to_erb(%(- x = "a # b"))
  end

  it "converts text with HTML in it" do
    assert_equal "<li><アクセス></li>", slim_to_erb("li <アクセス>")
    assert_equal "<p>Hello <code>x</code></p>", slim_to_erb("p Hello <code>x</code>")
  end

  it "converts case / when" do
    slim = "- case x\n- when 1\n  | one\n- else\n  | other"
    assert_equal "<% case x %><% when 1 %>one<% else %>other<% end %>", slim_to_erb(slim)
  end

  it "puts nothing between case and the first when, since Erubi can't compile it" do
    slim = "tr\n  - if a\n    th x\n  - case k\n  - when 1\n    td one\n  - when 2\n    td two"
    assert_match "<% case k %><% when 1 %>\n", slim_to_erb(slim)
  end

  it "keeps strict locals, which Rails reads from the template source" do
    assert_equal "<%# locals: (path:, network: nil) %>\n<p><%= path %></p>", slim_to_erb("/# locals: (path:, network: nil)\np = path")
    assert_equal "<p>x</p>", slim_to_erb("/ locals are documented elsewhere\np x")
    assert_equal "<!--# locals: (path:)-->", slim_to_erb("/!# locals: (path:)")
  end

  it "converts blocks and adds the do Slim adds" do
    assert_equal "<% items.each do |item| %><%= item %><% end %>", slim_to_erb("- items.each do |item|\n  = item")
    assert_equal "<% items.each do %><%= 1 %><% end %>", slim_to_erb("- items.each\n  = 1")
    assert_equal "<%= link_to url do %>Go<% end %>", slim_to_erb("= link_to url do\n  | Go")
  end

  it "expands data and aria hashes like Slim" do
    assert_equal %(<p data-action="click" data-user_id="<%= user.id.to_s %>"></p>), slim_to_erb(%(p data={ action: "click", user_id: user.id.to_s }))
    assert_equal %(<p aria-label="x" data-a-b="1"></p>), slim_to_erb(%(p aria={ label: "x" } data={ a: { b: 1 } }))
  end

  it "falls back to tag.attributes for data and aria hashes that aren't literals" do
    converter = Herbst::Slim::Converter.new
    document = converter.convert("li data=option[:data] aria=labels")

    assert_equal %(<li <%= tag.attributes(aria: labels) %> <%= tag.attributes(data: option[:data]) %>></li>), Herbst::Printer.print(document, format: false)
    assert_equal 2, converter.warnings.size
  end

  it "converts attributes like Slim" do
    assert_equal %(<a href="<%= url_path %>" title="A &amp; B">x</a>), slim_to_erb(%(a href=url_path title="A & B" x))
    assert_equal %(<input checked type="checkbox">), slim_to_erb(%(input type="checkbox" checked=true disabled=false))
    assert_equal %(<input <%= "disabled" if off %>>), slim_to_erb("input disabled=off")
    assert_equal %(<p data-id="1"></p>), slim_to_erb("p data-id=1")
  end

  it "leaves out attributes whose value is nil or false, like Slim" do
    assert_equal %(<a <% if (attribute_value = url) %>href="<%= attribute_value %>"<% end %>>x</a>), slim_to_erb("a href=url x")
    assert_equal %(<script <% if (attribute_value = nonce) %>nonce="<%== attribute_value %>"<% end %>></script>), slim_to_erb("script nonce==nonce")
    assert_equal %(<p id="<%= dom_id(record) %>"></p>), slim_to_erb("p id=dom_id(record)")
    assert_equal %(<option <%= "selected" if on %> <% if (attribute_value = id) %>value="<%= attribute_value %>"<% end %>></option>),
                 slim_to_erb("option selected=on value=id")
  end

  it "keeps route helpers as plain attributes, but not methods on a receiver with the same suffix" do
    assert_equal %(<a href="<%= root_path %>">x</a>), slim_to_erb("a href=root_path x")
    assert_equal %(<a <% if (attribute_value = file.cloud_url) %>href="<%= attribute_value %>"<% end %>>x</a>), slim_to_erb("a href=file.cloud_url x")
    assert_equal %(<p title="<%= user.name.to_s %>"></p>), slim_to_erb("p title=user.name.to_s")
  end

  it "renders true as an empty attribute value, like Slim" do
    assert_equal %(<p <% if (attribute_value = (true if locked)) %>data-tip="<%= attribute_value unless attribute_value == true %>"<% end %>></p>),
                 slim_to_erb("p data-tip=(true if locked)")
    assert_equal %(<p <% if (attribute_value = user.admin?) %>title="<%= attribute_value unless attribute_value == true %>"<% end %>></p>),
                 slim_to_erb("p title=user.admin?")
  end

  it "merges classes" do
    assert_equal %(<p class="a <%= b %>"></p>), slim_to_erb("p.a class=b")
    assert_equal %(<p class="a b c"></p>), slim_to_erb(%(p.a class=["b", "c"]))
    assert_equal %(<p class="<%= [b, "c"].flatten.map(&:to_s).reject(&:empty?).join(" ") %>"></p>), slim_to_erb(%(p class=[b, "c"]))
  end

  it "leaves out a class that is nil or empty, like Slim" do
    assert_equal %(<p <% if (attribute_value = cls) && attribute_value != "" %>class="<%= attribute_value %>"<% end %>></p>), slim_to_erb("p class=cls")
  end

  it "leaves out a class that is only interpolation when it's empty, like Slim" do
    assert_equal %(<p <% if (attribute_value = (cls).to_s) && attribute_value != "" %>class="<%= attribute_value %>"<% end %>></p>), slim_to_erb(%(p class="\#{cls}"))
    assert_equal %(<p <% if (attribute_value = "\#{a}\#{b}") && attribute_value != "" %>class="<%= attribute_value %>"<% end %>></p>), slim_to_erb(%(p class="\#{a}\#{b}"))
    assert_equal %(<p class="<%= a %> b"></p>), slim_to_erb(%(p class="\#{a} b"))
  end

  it "wraps class code that starts with [ but isn't an Array literal" do
    code = %([a, b].compact.join(" ").presence)
    expected = %([#{code}].flatten.map(&:to_s).reject(&:empty?).join(" "))

    assert_equal %(<p <% if (attribute_value = #{expected}) && attribute_value != "" %>class="<%= attribute_value %>"<% end %>></p>), slim_to_erb("p class=#{code}")
  end

  it "falls back to tag.attributes for splats" do
    converter = Herbst::Slim::Converter.new
    document = converter.convert("p *attrs")

    assert_equal %(<p <%= tag.attributes(**attrs) %>></p>), Herbst::Printer.print(document, format: false)
    assert_equal 1, converter.warnings.size
  end

  it "converts comments and doctypes" do
    assert_equal "<!DOCTYPE html>\n<!--visible-->", slim_to_erb("doctype html\n/ hidden\n/! visible")
    assert_equal "<!--[if IE]>\n  <p>ie</p>\n<![endif]-->", slim_to_erb("/[if IE]\n  p ie")
  end

  it "converts embedded engines" do
    assert_equal "<script>alert(<%= x %>);</script>", slim_to_erb("javascript:\n  alert(\#{x});")
    assert_equal "<style>p { color: red; }</style>", slim_to_erb("css:\n  p { color: red; }")
    assert_equal "<% x = 1 %>", slim_to_erb("ruby:\n  x = 1")
  end

  it "lets Herb build inline HTML" do
    erb = slim_to_erb(%(<div class="raw">\n  p in\n</div>))

    assert_equal %(<div class="raw">\n<p>in</p>\n</div>), erb
  end

  it "raises for unsupported embedded engines" do
    assert_raises(Herbst::UnsupportedError) { slim_to_erb("markdown:\n  # Hi") }
  end

  it "raises Herbst::Error for Slim syntax errors" do
    assert_raises(Herbst::Error) { slim_to_erb("p(") }
  end
end
