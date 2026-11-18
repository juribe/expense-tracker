xml.instruct!

xml.urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
  @entries.each do |entry|
    xml.url do
      xml.loc entry[:loc]
      xml.lastmod entry[:lastmod].utc.strftime("%Y-%m-%d") if entry[:lastmod].present?
    end
  end
end
