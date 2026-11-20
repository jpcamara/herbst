# frozen_string_literal: true

module Herbst
  module Slim
    class Parser < ::Slim::Parser
      DIRECTIVE = %r{\A/\s*((?:herb:|locals:).*)\z} #: Regexp

      # Rails reads strict locals from the template source, so a Slim comment like `/# locals: (...)`
      # declares them. Like Rails, the locals can continue on the following lines.
      STRICT_LOCALS = %r{\A/[ \t]*#[ \t]+(locals:[ \t]+\(.*?\))[ \t]*$}m #: Regexp

      attr_reader :dropped_directives #: Array[[Integer, String]]
      attr_reader :strict_locals #: String?

      #: (?Hash[Symbol, untyped]) -> void
      def initialize(options = {})
        super

        @dropped_directives = []
        @strict_locals = nil
      end

      protected

      #: () -> void
      def parse_comment_block
        directive = @line[DIRECTIVE, 1]
        @dropped_directives << [@lineno, directive.strip] if directive
        @strict_locals ||= comment_block[STRICT_LOCALS, 1]

        super
      end

      private

      #: () -> String
      def comment_block
        following = @lines.take_while { |line| line.match?(/\A\s*\z/) || get_indent(line) > @indents.fetch(-1) }

        [@line, *following].join("\n")
      end
    end
  end
end
