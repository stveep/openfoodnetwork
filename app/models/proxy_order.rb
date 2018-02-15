class ProxyOrder < ActiveRecord::Base
  belongs_to :order, class_name: 'Spree::Order', dependent: :destroy
  belongs_to :subscription
  belongs_to :order_cycle

  delegate :number, :completed_at, :total, to: :order, allow_nil: true

  scope :closed, -> { joins(:order_cycle).merge(OrderCycle.closed) }
  scope :not_closed, -> { joins(:order_cycle).merge(OrderCycle.not_closed) }
  scope :not_canceled, -> { where('proxy_orders.canceled_at IS NULL') }
  scope :placed_and_open, -> { joins(:order).not_closed.where(spree_orders: { state: 'complete' }) }

  def state
    # NOTE: the order is important here
    %w(canceled paused pending cart).each do |state|
      return state if send("#{state}?")
    end
    order.state
  end

  def canceled?
    canceled_at.present?
  end

  def cancel
    return false unless order_cycle.orders_close_at.andand > Time.zone.now
    transaction do
      update_column(:canceled_at, Time.zone.now)
      order.send('cancel') if order
      true
    end
  end

  def resume
    return false unless order_cycle.orders_close_at.andand > Time.zone.now
    transaction do
      update_column(:canceled_at, nil)
      order.send('resume') if order
      true
    end
  end

  def initialise_order!
    return order if order.present?
    create_order!(
      customer_id: subscription.customer_id,
      email: subscription.customer.email,
      order_cycle_id: order_cycle_id,
      distributor_id: subscription.shop_id,
      shipping_method_id: subscription.shipping_method_id
    )
    order.update_attribute(:user, subscription.customer.user)
    subscription.subscription_line_items.each do |sli|
      order.line_items.build(variant_id: sli.variant_id, quantity: sli.quantity, skip_stock_check: true)
    end
    order.update_attributes(bill_address: subscription.bill_address.dup, ship_address: subscription.ship_address.dup)
    order.update_distribution_charge!
    order.payments.create(payment_method_id: subscription.payment_method_id, amount: order.reload.total)

    save!
    order
  end

  private

  def paused?
    pending? && subscription.paused?
  end

  def pending?
    !order || order_cycle.orders_open_at > Time.zone.now
  end

  def cart?
    order.andand.state == 'complete' &&
      order_cycle.orders_close_at > Time.zone.now
  end
end
