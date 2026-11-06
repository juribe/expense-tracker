# frozen_string_literal: true

# ContactMessage
# Server-side form object for the public Contáctanos form.
#
# It normalizes the submitted values, validates the required fields and
# exposes the primitives used by ContactMailer. It is intentionally not
# persisted: the message is delivered by email.
#
# Example:
#   message = ContactMessage.new(name: "Ana", email: "ana@example.com",
#                                subject: "Soporte", message: "Hola")
#   message.valid? # => true
class ContactMessage
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations::Callbacks

  MAX_NAME_LENGTH = 120
  MAX_EMAIL_LENGTH = 254
  MAX_SUBJECT_LENGTH = 120
  MAX_MESSAGE_LENGTH = 5_000

  attribute :name, :string
  attribute :email, :string
  attribute :subject, :string
  attribute :message, :string
  attribute :website, :string

  before_validation :normalize

  validates :name, presence: true, length: { maximum: MAX_NAME_LENGTH }
  validates :email, presence: true, length: { maximum: MAX_EMAIL_LENGTH },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :subject, presence: true, length: { maximum: MAX_SUBJECT_LENGTH }
  validates :message, presence: true, length: { maximum: MAX_MESSAGE_LENGTH }
  validate :subject_has_no_line_breaks

  def spam?
    website.present?
  end

  def delivery_params
    {
      name: name,
      email: email,
      subject: subject,
      message: message
    }
  end

  private

  def normalize
    self.name = name.to_s.strip
    self.email = email.to_s.strip.downcase
    self.subject = subject.to_s.strip
    self.message = message.to_s.strip
  end

  # The subject is used in the email subject header. Reject CR/LF instead of
  # silently sanitizing it so a malformed request never reaches the mailer.
  def subject_has_no_line_breaks
    errors.add(:subject, :invalid) if subject.match?(/[\r\n]/)
  end
end
