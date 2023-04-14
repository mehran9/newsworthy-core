class ArticlesController < ApplicationController
  before_action :check_id

  def show
    redirect_to @url, status: 301
  end

  private
  def check_id
    return render_404 unless params.has_key?(:id) && !params[:id].empty?

    unless Rails.cache.exist?("article_#{params[:id]}")
      article = Article.where(id: params[:id]).first
      Rails.cache.write("article_#{params[:id]}", (article ? article['url'] : nil))
    end

    @url = Rails.cache.read("article_#{params[:id]}")
    render_404 unless @url
  end
end
