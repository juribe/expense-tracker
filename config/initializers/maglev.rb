# frozen_string_literal: true

Maglev.configure do |config|
  # Title of the Editor window
  # config.title = 'Maglev - Editor'
  # config.title = ->(site) { "#{site.name} 👋" }

  # Logo of the Editor (top left corner).
  # Put your custom logo in the app/assets/images folder of your Rails application.
  # config.logo = 'logo.png'
  # Or use the following option:
  # config.logo = ->(site) { site.siteable.avatar_url }
  # config.logo = ->(site) { ActionController::Base.helpers.asset_path('logo.png') }

  # Favicon (window tab)
  # Put your custom favicon in the app/assets/images folder of your Rails application.
  # config.favicon = 'favicon.ico'
  # Or use the following options:
  # config.favicon = ->(site) { site.siteable.favicon_url }
  # config.favicon = ->(site) { ActionController::Base.helpers.asset_path('favicon.png') }

  # Primary color of the Editor
  # config.primary_color = '#040712'

  # Action triggered when clicking on the very bottom left button in the Editor
  # NOTE: If you want the user to signed out from the Editor UI once the back action has been triggered,
  # you'll have to clear the `maglev_site_id` session variable.
  # config.back_action = 'https://www.mysite.dev' # External url
  # config.back_action = :my_account_path # name of the route in your Rails application
  # config.back_action = ->(site) { redirect_to main_app.my_account_path(site_id: site.id) }

  # Yogasto public site is Spanish only.
  # The first locale of the array is the default locale of the site.
  config.default_site_locales = [
    { label: 'Español', prefix: 'es' }
  ]

  # Editor UI authentication (https://docs.maglev.dev/guides/setup-authentication)
  # Yogasto reuses its Devise session: the editor is only available to users
  # flagged as admin (see ApplicationController#maglev_editor_allowed?).
  config.is_authenticated = :maglev_editor_allowed?

  # The bottom left button of the editor sends admins back to the app.
  config.back_action = :root_path

  # Paths already in use by the host application; content editors cannot
  # create CMS pages that collide with them.
  config.reserved_paths = %w(
    maglev users users/sign_in users/sign_up dashboard plans profile
    precios pricing prices settings reports expenses incomes budgets goals
    transfers imports financial_setup financial_chat financial_summary
    savings_opportunities drains
  )

  # Base class for Maglev::ApplicationController (inherit auth, layout, etc. from your app).
  # Set this in an initializer that runs before Maglev controllers are loaded
  # if you use something other than ApplicationController.
  # config.parent_controller = 'ApplicationController'

  # Uploader engine (:active_storage is the default one)
  # Checkout https://github.com/MarsBased/maglevcms-shrine for an example of a custom uploader
  # config.uploader = 'Maglev::Shrine::Uploader'
  config.uploader = :active_storage

  # Collections mapping (https://docs.maglev.dev/guides/setup-collections)
  # config.collections = {
  #   products: {
  #     model: 'Product',
  #     fields: {
  #       label: :name,
  #       image: :thumbnail_url
  #     }
  #   }
  # }

  # Pagination configuration
  # config.pagination = {
  #   pages: -1 # -1 means no pagination
  #   assets: 16 # number of assets displayed per page in the assets modal
  # }

  # Let your content editors references existing pages of your application but
  # not served/rendered by Maglev.
  # config.static_pages = [
  #   {
  #     title: { en: 'Products', fr: 'Produits' },
  #     path: { en: 'products', fr: 'fr/produits' }
  #   },
  #   {
  #     title: { en: 'Authentication', fr: 'Authentification' },
  #     path: { en: 'sign-in', fr: 'fr/se-connecter' }
  #   }
  # ]

  # Prevent the content editors to create pages sharing the same path with other
  # existing pages of the application.
  # config.reserved_paths = %w(products sign-in search posts/*)

  # Extra Tailwind CSS folders to watch for changes.
  # To be used if you need to implement a custom component in a folder of the main app.
  # config.tailwindcss_folders = []
end

# Small non-invasive extensions of Maglev CMS v3 without touching the gem:
# 1. Extra SEO fields (canonical_url, meta_robots) on Maglev::Page.
# 2. The editor "page" form accepts those extra fields.
# 3. The catch-all PreviewConstraint is relaxed to also serve content to
#    clients that send `Accept: */*` (curl, headless HTTP clients). The gem
#    only accepts html/xml formats or known crawlers; browsers and crawlers
#    keep working exactly the same.
Rails.application.config.to_prepare do
  Maglev::Page.include(Maglev::Page::SeoExtensionConcern)

  extra_seo_params = Module.new do
    def page_params
      params.require(:page).permit(
        :title, :path, :seo_title, :meta_description,
        :og_title, :og_description, :og_image_url,
        :canonical_url, :meta_robots, :visible, :lock_version
      )
    end
  end

  Maglev::Editor::PagesController.prepend(extra_seo_params)
  Maglev::Editor::PagesController.send(:private, :page_params)

  Maglev::PreviewConstraint.class_eval do
    protected

    def accepted_format?(request)
      symbol = request.format.symbol
      symbol.nil? || %i[html xml].include?(symbol)
    end
  end
end
