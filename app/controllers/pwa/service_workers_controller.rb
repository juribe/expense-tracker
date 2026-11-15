# Pwa::ServiceWorkersController
# GET /service-worker — root-scoped worker that serves the offline shell only.
module Pwa
  class ServiceWorkersController < ActionController::Base
    skip_forgery_protection

    def show
      response.headers["Cache-Control"] = "no-cache"
      response.headers["Service-Worker-Allowed"] = "/"

      render template: "pwa/service_worker", formats: [ :js ], content_type: "text/javascript"
    end
  end
end
