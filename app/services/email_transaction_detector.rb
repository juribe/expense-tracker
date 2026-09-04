# frozen_string_literal: true

# Cheap rule-based pre-filter that runs before any AI call. It identifies
# emails that should never create expenses (statements, promotions, security
# notices...) and flags special cases (refunds, reversals, failed charges).
#
# Emails that match no negative pattern are considered candidate transactions
# and are handed to the AI extractor for the final decision.
class EmailTransactionDetector
  Result = Struct.new(:transactional?, :reason, keyword_init: true)

  NON_TRANSACTIONAL_PATTERNS = {
    "credit card statement" => /estado\s+de\s+cuenta|extracto|resumen\s+de\s+tarjeta|cierre\s+de\s+tarjeta|statement|paysheet/i,
    "payment reminder" => /recordatorio\s+de\s+pago|pago\s+m[íi]nimo|minimum\s+payment|fecha\s+l[íi]mite\s+de\s+pago|payment\s+reminder/i,
    "promotion or marketing" => /promoci[oó]n|descuento|oferta\s+exclusiva|%(\s|\u00a0)*off|newsletter|marketing|rebaja|cup[oó]n|coupon|promo/i,
    "account balance notification" => /saldo\s+disponible|tu\s+saldo|account\s+balance|balance\s+notification|consulta\s+de\s+saldo/i,
    "security notification" => /alerta\s+de\s+seguridad|security\s+(alert|notification)|inicio\s+de\s+sesi[oó]n|nuevo\s+dispositivo|cambio\s+de\s+contrase[ñn]a|verify\s+your\s+(identity|account)|c[oó]digo\s+de\s+verificaci[oó]n/i
  }.freeze

  SPECIAL_PATTERNS = {
    "refund" => /\breembolso\b|\brefund\b|\bdevoluci[oó]n\b(?!.*compra)/i,
    "reversed transaction" => /reversad[oa]|reversed|contracargo|chargeback|anulaci[oó]n|anulad[ao]/i,
    "failed transaction" => /rechazad[ao]|declinad[oa]|declined|transacci[oó]n\s+fallida|fallid[ao]|insuficiente|insufficient|failed/i
  }.freeze

  def call(subject:, body:)
    text = "#{subject}\n#{body}".to_s.dup.force_encoding(Encoding::UTF_8)

    NON_TRANSACTIONAL_PATTERNS.each do |reason, pattern|
      next unless text.match?(pattern)

      return Result.new(transactional?: false, reason: reason)
    end

    SPECIAL_PATTERNS.each do |reason, pattern|
      next unless text.match?(pattern)

      return Result.new(transactional?: false, reason: reason)
    end

    Result.new(transactional?: true, reason: nil)
  end
end
