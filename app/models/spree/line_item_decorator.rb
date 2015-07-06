Spree::LineItem.class_eval do
  attr_accessible :max_quantity, :unit_value
  attr_accessible :unit_value, :price, :as => :api

  # -- Scopes
  scope :managed_by, lambda { |user|
    if user.has_spree_role?('admin')
      scoped
    else
      # Find line items that are from orders distributed by the user or supplied by the user
      joins(:variant => :product).
      joins(:order).
      where('spree_orders.distributor_id IN (?) OR spree_products.supplier_id IN (?)', user.enterprises, user.enterprises).
      select('spree_line_items.*')
    end
  }

  scope :supplied_by, lambda { |enterprise|
    joins(:product).
    where('spree_products.supplier_id = ?', enterprise)
  }
  scope :supplied_by_any, lambda { |enterprises|
    joins(:product).
    where('spree_products.supplier_id IN (?)', enterprises)
  }

  scope :with_tax, joins(:adjustments).
                   where('spree_adjustments.originator_type = ?', 'Spree::TaxRate').
                   select('DISTINCT spree_line_items.*')

  # Line items without a Spree::TaxRate-originated adjustment
  scope :without_tax, joins("LEFT OUTER JOIN spree_adjustments ON (spree_adjustments.adjustable_id=spree_line_items.id AND spree_adjustments.adjustable_type = 'Spree::LineItem' AND spree_adjustments.originator_type='Spree::TaxRate')").
                      where('spree_adjustments.id IS NULL')


  def price_with_adjustments
    # EnterpriseFee#create_locked_adjustment applies adjustments on line items to their parent order,
    # so line_item.adjustments returns an empty array
    return 0 if quantity == 0
    (price + order.adjustments.where(source_id: id).sum(&:amount) / quantity).round(2)
  end

  def single_display_amount_with_adjustments
    Spree::Money.new(price_with_adjustments, { :currency => currency })
  end

  def amount_with_adjustments
    # We calculate from price_with_adjustments here rather than building our own value because
    # rounding errors can produce discrepencies of $0.01.
    price_with_adjustments * quantity
  end

  def display_amount_with_adjustments
    Spree::Money.new(amount_with_adjustments, { :currency => currency })
  end
end
