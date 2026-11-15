# Pwa::ManifestsController
# GET /manifest — public web app manifest used by installable browsers.
module Pwa
  class ManifestsController < ActionController::Base
    ICONS = [
      { src: "/pwa/icon-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
      { src: "/pwa/icon-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
      { src: "/pwa/maskable-192.png", sizes: "192x192", type: "image/png", purpose: "maskable" },
      { src: "/pwa/maskable-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" }
    ].freeze

    def show
      response.headers["Cache-Control"] = "no-cache"

      render json: manifest, content_type: "application/manifest+json"
    end

    private

    def manifest
      {
        id: "/",
        name: AppName.current,
        short_name: AppName.current,
        description: "Controla tus finanzas personales con #{AppName.current}.",
        lang: "es",
        start_url: "/",
        scope: "/",
        display: "standalone",
        orientation: "portrait",
        theme_color: Pwa::THEME_COLOR,
        background_color: Pwa::BACKGROUND_COLOR,
        icons: ICONS
      }
    end
  end
end
