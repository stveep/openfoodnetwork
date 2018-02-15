Spree::PaymentMethod.class_eval do
  include Spree::Core::CalculatedAdjustments

  acts_as_taggable

  has_and_belongs_to_many :distributors, join_table: 'distributors_payment_methods', :class_name => 'Enterprise', association_foreign_key: 'distributor_id'
  has_many :credit_cards, class_name: "Spree::CreditCard" # from Spree v.2.3.0 d470b31798f37

  attr_accessible :distributor_ids, :tag_list

  after_initialize :init

  validates_with DistributorsValidator

  # -- Scopes
  scope :managed_by, lambda { |user|
    if user.has_spree_role?('admin')
      scoped
    else
      joins(:distributors).
        where('distributors_payment_methods.distributor_id IN (?)', user.enterprises).
        select('DISTINCT spree_payment_methods.*')
    end
  }

  scope :for_distributor, lambda { |distributor|
    joins(:distributors).
      where('enterprises.id = ?', distributor)
  }

  scope :for_subscriptions, where(type: Subscription::ALLOWED_PAYMENT_METHOD_TYPES)

  scope :by_name, order('spree_payment_methods.name ASC')

  # Rewrite Spree's ruby-land class method as a scope
  scope :available, lambda { |display_on='both'|
    where(active: true).
      where('spree_payment_methods.display_on=? OR spree_payment_methods.display_on=? OR spree_payment_methods.display_on IS NULL', display_on, '').
      where('spree_payment_methods.environment=? OR spree_payment_methods.environment=? OR spree_payment_methods.environment IS NULL', Rails.env, '')
  }

  def init
    unless reflections.keys.include? :calculator
      self.class.include Spree::Core::CalculatedAdjustments
    end

    self.calculator ||= Spree::Calculator::FlatRate.new(preferred_amount: 0)
  end

  def has_distributor?(distributor)
    self.distributors.include?(distributor)
  end

  def self.clean_name
    case name
    when "Spree::PaymentMethod::Check"
      "Cash/EFT/etc. (payments for which automatic validation is not required)"
    when "Spree::Gateway::Migs"
      "MasterCard Internet Gateway Service (MIGS)"
    when "Spree::Gateway::Pin"
      "Pin Payments"
    when "Spree::Gateway::StripeConnect"
      "Stripe"
    when "Spree::Gateway::PayPalExpress"
      "PayPal Express"
    else
      i = name.rindex('::') + 2
      name[i..-1]
    end
  end
end
