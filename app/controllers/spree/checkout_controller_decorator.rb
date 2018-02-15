require 'open_food_network/address_finder'

Spree::CheckoutController.class_eval do

  include CheckoutHelper

  before_filter :enable_embedded_shopfront

  def edit
    flash.keep
    redirect_to main_app.checkout_path
  end

  private

  def before_payment
    current_order.payments.destroy_all if request.put?
  end

  # Adapted from spree_last_address gem: https://github.com/TylerRick/spree_last_address
  # Originally, we used a forked version of this gem, but encountered strange errors where
  # it worked in dev but only intermittently in staging/prod.
  def before_address
    associate_user

    finder = OpenFoodNetwork::AddressFinder.new(@order.email)

    @order.bill_address = finder.bill_address
    @order.ship_address = finder.ship_address
  end
end
