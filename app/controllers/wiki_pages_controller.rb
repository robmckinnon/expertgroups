class WikiPagesController < ApplicationController

  acts_as_wiki_pages_controller

  def show
    if params['path'] && params['path'].strip.empty?
      redirect_to '/'
    else
      super
    end
  end

  def history_allowed?
    false
  end

  def edit_allowed?
    false
  end

  def destroy_allowed?
    false
  end

end
