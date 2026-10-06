# frozen_string_literal: true

# One-off + rerunnable backfill: links debt payments registered BEFORE the
# Payments::RecurringLink hook existed to their matching recurring templates,
# so Día de Cuadre stops listing cuotas that were already paid through
# money_sources/:id/payments.
#
#   bin/rails reconciliation:backfill_payments            # applies
#   bin/rails reconciliation:backfill_payments DRY_RUN=1  # report only
#
# Uses the same strict matching rules as the live hook: only unlinked
# expenses, exactly one active expense template of the same amount for that
# month, same debt source wins tie-breaks, ambiguity stays untouched.
namespace :reconciliation do
  desc "Link existing debt payments to their recurring templates (DRY_RUN=1 to report only)"
  task backfill_payments: :environment do
    dry_run = ENV["DRY_RUN"].present?

    eligible = Payment.joins(:expense).where(transactions: { recurring_template_id: nil })
    puts "Payments found: #{Payment.count}, with unlinked expense: #{eligible.count}"

    linked = skipped = 0
    eligible.includes(:expense, :money_source).find_each do |payment|
      template = Payments::RecurringLink.call(
        user: payment.user,
        expense: payment.expense,
        money_source: payment.money_source,
        assign: !dry_run
      )

      if template
        linked += 1
        puts "  #{dry_run ? 'WOULD LINK' : 'LINKED'} payment##{payment.id} (user #{payment.user_id}) -> template##{template.id} #{template.description}"
      else
        skipped += 1
        puts "  SKIPPED payment##{payment.id} (user #{payment.user_id}) — no unambiguous match"
      end
    end

    mode = dry_run ? "[dry run] " : ""
    puts "#{mode}Linked: #{linked}, skipped: #{skipped}"
  end
end
