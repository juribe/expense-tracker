class User < ApplicationRecord
  has_many :memberships, as: :owner, class_name: "PaymentEngine::Membership"
  has_many :purchases, as: :owner, class_name: "PaymentEngine::Purchase"
end
