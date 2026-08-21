# frozen_string_literal: true

module RSX
  # ActionView handler for .rsx templates: app/views/users/show.html.rsx
  #
  # The handler returns Ruby source, which ActionView compiles into a method on
  # the view context. That means a .rsx view is compiled once per process and
  # every Rails helper (url helpers, `t`, form builders, CSRF tags) is available
  # directly, because `self` inside the template is the view.
  class TemplateHandler
    class << self
      # ActionView passes (template) on older versions and (template, source)
      # on 6.0+.
      def call(template, source = nil)
        source ||= template.source
        identifier = template.respond_to?(:identifier) ? template.identifier : nil
        compile(source, identifier)
      end

      def compile(source, identifier = nil)
        ruby = RSX.compile(source, path: identifier)

        # Everything is kept on one line up to the body so that line numbers in
        # the compiled method still match the .rsx file.
        +"__rsx_value = begin;" << ruby << "\nend\n::RSX.template_result(__rsx_value)\n"
      end

      # Templates render markup, not a component, so there is nothing to escape
      # on the way out.
      def handles_encoding?
        true
      end
    end
  end
end
