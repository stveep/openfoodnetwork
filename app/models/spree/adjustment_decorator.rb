module Spree
  Adjustment.class_eval do
    # Deletion of metadata is handled in the database.
    # So we don't need the option `dependent: :destroy` as long as
    # AdjustmentMetadata has no destroy logic itself.
    has_one :metadata, class_name: 'AdjustmentMetadata'

    scope :enterprise_fee, where(originator_type: 'EnterpriseFee')
    scope :included_tax, where(originator_type: 'Spree::TaxRate', adjustable_type: 'Spree::LineItem')
    scope :with_tax,    where('spree_adjustments.included_tax > 0')
    scope :without_tax, where('spree_adjustments.included_tax = 0')

    attr_accessible :included_tax

    def set_included_tax!(rate)
      tax = amount - (amount / (1 + rate))
      set_absolute_included_tax! tax
    end

    def set_absolute_included_tax!(tax)
      update_attributes! included_tax: tax.round(2)
    end
  end
end
