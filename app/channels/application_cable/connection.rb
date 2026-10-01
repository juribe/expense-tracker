# Application Cable connection: every stream is scoped to a signed-in user.
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      user = env["warden"].user
      raise "Connection requires a signed-in user" unless user

      user
    end
  end
end
