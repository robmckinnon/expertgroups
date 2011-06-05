class IncreaseContentTextLimit < ActiveRecord::Migration
  def self.up
    change_column :wiki_pages, :content, :text, :limit => 65537
    change_column :wiki_page_versions, :content, :text, :limit => 65537
  end

  def self.down
  end
end
