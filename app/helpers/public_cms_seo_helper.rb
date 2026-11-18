# PublicCmsSeoHelper
# Builds the JSON-LD graph rendered by the public Maglev layout: Organization,
# WebSite, SoftwareApplication, BreadcrumbList and Article entities.
#
# Example: public_cms_seo_data(maglev_page)
module PublicCmsSeoHelper
  def public_cms_seo_data(page, base_url: public_cms_base_url)
    [
      public_cms_organization_data,
      public_cms_website_data,
      public_cms_software_application_data,
      public_cms_breadcrumb_data(page, base_url),
      public_cms_article_data(page, base_url)
    ].compact
  end

  # Structured data for the host-application pricing page, which is not a
  # Maglev page but is listed in the sitemap.
  def public_cms_pricing_seo_data
    [
      public_cms_organization_data,
      public_cms_website_data,
      public_cms_software_application_data,
      {
        "@context" => "https://schema.org",
        "@type" => "BreadcrumbList",
        "itemListElement" => [
          {
            "@type" => "ListItem",
            "position" => 1,
            "name" => "Inicio",
            "item" => "#{public_cms_base_url}/"
          },
          {
            "@type" => "ListItem",
            "position" => 2,
            "name" => "Precios y planes",
            "item" => "#{public_cms_base_url}/precios"
          }
        ]
      }
    ]
  end

  private

  def public_cms_organization_data
    {
      "@context" => "https://schema.org",
      "@type" => "Organization",
      "@id" => "#{public_cms_base_url}/#organization",
      "name" => app_name,
      "url" => "#{public_cms_base_url}/",
      "logo" => {
        "@type" => "ImageObject",
        "url" => "#{public_cms_base_url}/brand/yogasto-logo-claro.svg"
      },
      "description" => "Aplicación para organizar gastos, ingresos, cuentas, tarjetas, presupuestos y metas personales."
    }
  end

  def public_cms_website_data
    {
      "@context" => "https://schema.org",
      "@type" => "WebSite",
      "@id" => "#{public_cms_base_url}/#website",
      "name" => app_name,
      "url" => "#{public_cms_base_url}/",
      "inLanguage" => "es-CO",
      "publisher" => { "@id" => "#{public_cms_base_url}/#organization" },
      "potentialAction" => {
        "@type" => "SearchAction",
        "target" => {
          "@type" => "EntryPoint",
          "urlTemplate" => "#{public_cms_base_url}/ayuda?q={search_term_string}"
        },
        "query-input" => "required name=search_term_string"
      }
    }
  end

  def public_cms_software_application_data
    data = {
      "@context" => "https://schema.org",
      "@type" => "SoftwareApplication",
      "@id" => "#{public_cms_base_url}/#software",
      "name" => app_name,
      "url" => "#{public_cms_base_url}/",
      "applicationCategory" => "FinanceApplication",
      "operatingSystem" => "Web",
      "inLanguage" => "es-CO",
      "description" => "Aplicación web para registrar y organizar gastos e ingresos, cuentas, tarjetas de crédito, presupuestos, metas y reportes financieros personales.",
      "publisher" => { "@id" => "#{public_cms_base_url}/#organization" }
    }

    offers = public_cms_software_offers
    data["offers"] = offers if offers.any?
    data
  end

  def public_cms_software_offers
    options = PaymentEngine::PaymentOption.active.order(:position).to_a
    paid_offers = options.uniq { |option| [ option.price.to_i, option.currency ] }.map do |option|
      {
        "@type" => "Offer",
        "name" => paid_plan_name(option),
        "price" => option.price.to_i.to_s,
        "priceCurrency" => option.currency.presence || "COP",
        "url" => "#{public_cms_base_url}/precios"
      }
    end

    [ free_plan_offer ] + paid_offers
  rescue StandardError
    [ free_plan_offer ]
  end

  def paid_plan_name(option)
    return "Plan Anual" if option.access_duration_unit.to_s == "year"
    return "Plan Anual" if option.interval.blank? && option.access_duration_count.to_i >= 12
    return "Plan Mensual" if option.interval.to_s == "month"

    option.name
  end

  def free_plan_offer
    {
      "@type" => "Offer",
      "name" => "Plan Gratis",
      "price" => "0",
      "priceCurrency" => "COP",
      "url" => "#{public_cms_base_url}/precios"
    }
  end

  def public_cms_breadcrumb_data(page, base_url)
    return if page.index?

    items = if help_center_page?(page)
      help_center_breadcrumbs(page)
    else
      [ { label: "Inicio", url: "/" }, { label: page.title, url: nil } ]
    end

    {
      "@context" => "https://schema.org",
      "@type" => "BreadcrumbList",
      "itemListElement" => items.each_with_index.map do |item, index|
        {
          "@type" => "ListItem",
          "position" => index + 1,
          "name" => item[:label],
          "item" => item[:url] ? "#{base_url}#{item[:url]}" : public_cms_canonical_url(page)
        }
      end
    }
  end

  def public_cms_article_data(page, base_url)
    return unless help_center_article_page?(page)

    article = help_center_article_index(page)
    category = HelpCategoryIndex.find_by(
      locale: HelpCenter::LOCALE,
      path: HelpCenter::PagePath.new(page.path).category_path
    )

    {
      "@context" => "https://schema.org",
      "@type" => [ "Article", "TechArticle" ],
      "headline" => page.title,
      "description" => page.meta_description,
      "inLanguage" => "es-CO",
      "datePublished" => (article&.published_at || page.published_at)&.iso8601,
      "dateModified" => (article&.published_at || page.published_at || page.updated_at)&.iso8601,
      "mainEntityOfPage" => public_cms_canonical_url(page),
      "articleSection" => category&.name,
      "author" => { "@type" => "Organization", "name" => app_name },
      "publisher" => { "@id" => "#{base_url}/#organization" },
      "isPartOf" => { "@id" => "#{base_url}/#website" }
    }.compact
  end

  def app_name
    AppName.current
  end
end
