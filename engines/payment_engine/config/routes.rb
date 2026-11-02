PaymentEngine::Engine.routes.draw do
  post "webhooks/:provider", to: "webhooks#create", as: :webhook
end
