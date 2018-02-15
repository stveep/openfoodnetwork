require 'open_food_network/address_finder'

class CheckoutController < Spree::CheckoutController
  layout 'darkswarm'

  prepend_before_filter :check_hub_ready_for_checkout
  prepend_before_filter :check_order_cycle_expiry
  prepend_before_filter :require_order_cycle
  prepend_before_filter :require_distributor_chosen

  skip_before_filter :check_registration
  before_filter :enable_embedded_shopfront

  include OrderCyclesHelper
  include EnterprisesHelper

  def edit
    # This is only required because of spree_paypal_express. If we implement
    # a version of paypal that uses this controller, and more specifically
    # the #update_failed method, then we can remove this call
    restart_checkout
  end

  def update
    if @order.update_attributes(object_params)
      check_order_for_phantom_fees
      fire_event('spree.checkout.update')
      while @order.state != "complete"
        if @order.state == "payment"
          return if redirect_to_paypal_express_form_if_needed
        end

        next if advance_order_state(@order)

        if @order.errors.present?
          flash[:error] = @order.errors.full_messages.to_sentence
        else
          flash[:error] = t(:payment_processing_failed)
        end
        update_failed
        return
      end
      if @order.state == "complete" ||  @order.completed?
        set_default_bill_address
        set_default_ship_address

        ResetOrderService.new(self, current_order).call
        session[:access_token] = current_order.token

        flash[:notice] = t(:order_processed_successfully)
        respond_to do |format|
          format.html do
            respond_with(@order, :location => order_path(@order))
          end
          format.json do
            render json: {path: order_path(@order)}, status: 200
          end
        end
      else
        update_failed
      end
    else
      update_failed
    end
  end

  # Clears the cached order. Required for #current_order to return a new order
  # to serve as cart. See https://github.com/spree/spree/blob/1-3-stable/core/lib/spree/core/controller_helpers/order.rb#L14
  # for details.
  def expire_current_order
    session[:order_id] = nil
    @current_order = nil
  end

  private

  def set_default_bill_address
    if params[:order][:default_bill_address]
      new_bill_address = @order.bill_address.clone.attributes

      user_bill_address_id = spree_current_user.bill_address.andand.id
      spree_current_user.update_attributes(bill_address_attributes: new_bill_address.merge('id' => user_bill_address_id))

      customer_bill_address_id = @order.customer.bill_address.andand.id
      @order.customer.update_attributes(bill_address_attributes: new_bill_address.merge('id' => customer_bill_address_id))
    end

  end

  def set_default_ship_address
    if params[:order][:default_ship_address]
      new_ship_address = @order.ship_address.clone.attributes

      user_ship_address_id = spree_current_user.ship_address.andand.id
      spree_current_user.update_attributes(ship_address_attributes: new_ship_address.merge('id' => user_ship_address_id))

      customer_ship_address_id = @order.customer.ship_address.andand.id
      @order.customer.update_attributes(ship_address_attributes: new_ship_address.merge('id' => customer_ship_address_id))
    end
  end

  def check_order_for_phantom_fees
    phantom_fees = @order.adjustments.joins('LEFT OUTER JOIN spree_line_items ON spree_line_items.id = spree_adjustments.source_id').
      where("originator_type = 'EnterpriseFee' AND source_type = 'Spree::LineItem' AND spree_line_items.id IS NULL")

    if phantom_fees.any?
      Bugsnag.notify(RuntimeError.new("Phantom Fees"), {
        phantom_fees: {
          phantom_total: phantom_fees.sum(&:amount).to_s,
          phantom_fees: phantom_fees.as_json
        }
      })
    end
  end

  # Copied and modified from spree. Remove check for order state, since the state machine is
  # progressed all the way in one go with the one page checkout.
  def object_params
    # For payment step, filter order parameters to produce the expected nested attributes for a single payment and its source, discarding attributes for payment methods other than the one selected
    if params[:payment_source].present? && source_params = params.delete(:payment_source)[params[:order][:payments_attributes].first[:payment_method_id].underscore]
      params[:order][:payments_attributes].first[:source_attributes] = source_params
    end
    if (params[:order][:payments_attributes])
      params[:order][:payments_attributes].first[:amount] = @order.total
    end
    if params[:order][:existing_card_id]
      construct_saved_card_attributes
    end
    params[:order]
  end

  # Perform order.next, guarding against StaleObjectErrors
  def advance_order_state(order)
    tries ||= 3
    order.next

  rescue ActiveRecord::StaleObjectError
    retry unless (tries -= 1).zero?
    false
  end

  def update_failed
    clear_ship_address
    restart_checkout
    respond_to do |format|
      format.html do
        render :edit
      end
      format.json do
        render json: {errors: @order.errors, flash: flash.to_hash}.to_json, status: 400
      end
    end
  end

  # When we have a pickup Shipping Method, we clone the distributor address into ship_address before_save
  # We don't want this data in the form, so we clear it out
  def clear_ship_address
    unless current_order.shipping_method.andand.require_ship_address
      current_order.ship_address = Spree::Address.default
    end
  end

  def restart_checkout
    return if @order.state == 'cart'
    @order.restart_checkout! # resets state to 'cart'
    @order.update_attributes!(shipping_method_id: nil)
    @order.shipments.with_state(:pending).destroy_all
    @order.payments.with_state(:checkout).destroy_all
    @order.reload
  end

  def skip_state_validation?
    true
  end

  def load_order
    @order = current_order
    redirect_to main_app.shop_path and return unless @order and @order.checkout_allowed?
    raise_insufficient_quantity and return if @order.insufficient_stock_lines.present?
    redirect_to main_app.shop_path and return if @order.completed?
    before_address
    setup_for_current_state
  end

  def before_address
    associate_user

    finder = OpenFoodNetwork::AddressFinder.new(@order.email, @order.customer, spree_current_user)

    @order.bill_address = finder.bill_address
    @order.ship_address = finder.ship_address
  end

  # Overriding Spree's methods
  def raise_insufficient_quantity
    respond_to do |format|
      format.html do
        redirect_to cart_path
      end

      format.json do
        render json: {path: cart_path}, status: 400
      end
    end
  end

  def redirect_to_paypal_express_form_if_needed
    return unless params[:order][:payments_attributes]

    payment_method = Spree::PaymentMethod.find(params[:order][:payments_attributes].first[:payment_method_id])
    return unless payment_method.kind_of?(Spree::Gateway::PayPalExpress)

    render json: {path: spree.paypal_express_url(payment_method_id: payment_method.id)}, status: 200
    true
  end

  def construct_saved_card_attributes
    existing_card_id = params[:order].delete(:existing_card_id)
    return if existing_card_id.blank?

    credit_card = Spree::CreditCard.find(existing_card_id)
    if credit_card.try(:user_id).blank? || credit_card.user_id != spree_current_user.try(:id)
      raise Spree::Core::GatewayError, I18n.t(:invalid_credit_card)
    end

    # Not currently supported but maybe we should add it...?
    credit_card.verification_value = params[:cvc_confirm] if params[:cvc_confirm].present?

    params[:order][:payments_attributes].first[:source] = credit_card
    params[:order][:payments_attributes].first.delete :source_attributes
  end

  def rescue_from_spree_gateway_error(error)
    flash[:error] = t(:spree_gateway_error_flash_for_checkout, error: error.message)
    respond_to do |format|
      format.html { render :edit }
      format.json { render json: { flash: flash.to_hash }, status: 400 }
    end
  end
end
