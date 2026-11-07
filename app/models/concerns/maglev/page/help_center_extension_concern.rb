# Maglev::Page::HelpCenterExtensionConcern
# Keeps the help center projection in sync when a Maglev page is saved or removed.
#
# Example: publishing a page under /ayuda updates HelpArticleIndex.
module Maglev
  module Page::HelpCenterExtensionConcern
    extend ActiveSupport::Concern

    included do
      after_save :sync_help_center_index
      after_destroy :delete_help_center_index
    end

    private

    def sync_help_center_index
      return unless help_center_index_relevant?

      HelpCenter::Indexer.new(self).call
    end

    def delete_help_center_index
      HelpCategoryIndex.where(maglev_page_id: id).delete_all
      HelpArticleIndex.where(maglev_page_id: id).delete_all
    end

    def help_center_index_relevant?
      current_path = path_hash[HelpCenter::LOCALE].to_s

      current_path == HelpCenter::PagePath::ROOT || current_path.start_with?("#{HelpCenter::PagePath::ROOT}/") ||
        HelpCategoryIndex.where(maglev_page_id: id).exists? ||
        HelpArticleIndex.where(maglev_page_id: id).exists?
    end
  end
end
