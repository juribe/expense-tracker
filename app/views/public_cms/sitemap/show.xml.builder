xml.instruct!

xml.urlset xmlns: "http://www.google.com/schemas/sitemap/0.9" do
  @pages.each do |page|
    fullpath = page.index? ? "#{@host}/" : "#{@host}/#{page.path}"

    xml.url do
      xml.loc fullpath
      xml.lastmod page.published_at.strftime("%Y-%m-%d")
    end
  end
end
