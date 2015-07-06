class HomeController < BaseController
  layout 'darkswarm'

  def index
    @num_distributors = Enterprise.is_distributor.activated.visible.count
    @num_producers = Enterprise.is_primary_producer.activated.visible.count
    @num_users = Spree::User.joins(:orders).merge(Spree::Order.complete).count('DISTINCT spree_users.*')
    @num_orders = Spree::Order.complete.count
  end

  def about_us
  end
end
