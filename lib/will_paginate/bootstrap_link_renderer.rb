require "will_paginate/view_helpers/action_view"

module WillPaginate
  module ActionView
    # Bootstrap 5 markup for will_paginate links, wrapped in a nav that keeps
    # the data-testid record the test suite anchors on.
    class BootstrapLinkRenderer < LinkRenderer
      ELLIPSIS = "&hellip;".freeze

      def to_html
        list_items = pagination.map { |item| item.is_a?(Integer) ? page_number(item) : send(item) }
                              .join(@options[:link_separator])

        list = tag(:ul, list_items, class: "pagination justify-content-center mb-0")
        tag(:nav, list, container_attributes.merge("data-testid" => "pagination"))
      end

      protected

      def page_number(page)
        if page == current_page
          tag(:li, tag(:span, page, class: "page-link"), class: "page-item active")
        else
          tag(:li, link(page, page, class: "page-link", rel: rel_value(page),
                                      "aria-label": page_aria_label(page)),
                class: "page-item")
        end
      end

      def previous_or_next_page(page, text, classname, _aria_label = nil)
        if page
          tag(:li, link(text, page, class: "page-link"), class: "page-item")
        else
          tag(:li, tag(:span, text, class: "page-link"), class: "page-item disabled")
        end
      end

      def gap
        tag(:li, tag(:span, ELLIPSIS.html_safe, class: "page-link"), class: "page-item disabled")
      end

      private

      def page_aria_label(page)
        @template.will_paginate_translate(:page_aria_label, page: page.to_i) { "Page #{page}" }
      end
    end
  end
end
