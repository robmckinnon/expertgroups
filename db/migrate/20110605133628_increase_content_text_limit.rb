class IncreaseContentTextLimit < ActiveRecord::Migration
  def self.up
    if Rails.env == 'development'
      change_column :wiki_pages, :content, :text, :limit => 65537
      change_column :wiki_page_versions, :content, :text, :limit => 65537
    end
  end

  def self.down
  end
end
