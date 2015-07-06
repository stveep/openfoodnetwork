require 'ffaker'
require 'spree/core/testing_support/factories'

FactoryGirl.define do
  factory :classification, class: Spree::Classification do
  end

  factory :order_cycle, :parent => :simple_order_cycle do
    coordinator_fees { [create(:enterprise_fee, enterprise: coordinator)] }

    after(:create) do |oc|
      # Suppliers
      supplier1 = create(:supplier_enterprise)
      supplier2 = create(:supplier_enterprise)

      # Incoming Exchanges
      ex1 = create(:exchange, :order_cycle => oc, :incoming => true,
                   :sender => supplier1, :receiver => oc.coordinator)
      ex2 = create(:exchange, :order_cycle => oc, :incoming => true,
                   :sender => supplier2, :receiver => oc.coordinator)
      ExchangeFee.create!(exchange: ex1,
                          enterprise_fee: create(:enterprise_fee, enterprise: ex1.sender))
      ExchangeFee.create!(exchange: ex2,
                          enterprise_fee: create(:enterprise_fee, enterprise: ex2.sender))

      #Distributors
      distributor1 = create(:distributor_enterprise)
      distributor2 = create(:distributor_enterprise)

      # Outgoing Exchanges
      ex3 = create(:exchange, :order_cycle => oc, :incoming => false,
                   :sender => oc.coordinator, :receiver => distributor1,
                   :pickup_time => 'time 0', :pickup_instructions => 'instructions 0')
      ex4 = create(:exchange, :order_cycle => oc, :incoming => false,
                   :sender => oc.coordinator, :receiver => distributor2,
                   :pickup_time => 'time 1', :pickup_instructions => 'instructions 1')
      ExchangeFee.create!(exchange: ex3,
                          enterprise_fee: create(:enterprise_fee, enterprise: ex3.receiver))
      ExchangeFee.create!(exchange: ex4,
                          enterprise_fee: create(:enterprise_fee, enterprise: ex4.receiver))

      # Products with images
      [ex1, ex2].each do |exchange|
        product = create(:product, supplier: exchange.sender)
        image = File.open(File.expand_path('../../app/assets/images/logo-white.png', __FILE__))
        Spree::Image.create({:viewable_id => product.master.id, :viewable_type => 'Spree::Variant', :alt => "position 1", :attachment => image, :position => 1})

        exchange.variants << product.variants.first
      end

      variants = [ex1, ex2].map(&:variants).flatten
      [ex3, ex4].each do |exchange|
        variants.each { |v| exchange.variants << v }
      end
    end
  end

  factory :simple_order_cycle, :class => OrderCycle do
    sequence(:name) { |n| "Order Cycle #{n}" }

    orders_open_at  { Time.zone.now - 1.day }
    orders_close_at { Time.zone.now + 1.week }

    coordinator { Enterprise.is_distributor.first || FactoryGirl.create(:distributor_enterprise) }

    ignore do
      suppliers []
      distributors []
      variants []
    end

    after(:create) do |oc, proxy|
      proxy.suppliers.each do |supplier|
        ex = create(:exchange, :order_cycle => oc, :sender => supplier, :receiver => oc.coordinator, :incoming => true, :pickup_time => 'time', :pickup_instructions => 'instructions')
        proxy.variants.each { |v| ex.variants << v }
      end

      proxy.distributors.each do |distributor|
        ex = create(:exchange, :order_cycle => oc, :sender => oc.coordinator, :receiver => distributor, :incoming => false, :pickup_time => 'time', :pickup_instructions => 'instructions')
        proxy.variants.each { |v| ex.variants << v }
      end
    end
  end

  factory :exchange, :class => Exchange do
    order_cycle { OrderCycle.first || FactoryGirl.create(:simple_order_cycle) }
    sender      { FactoryGirl.create(:enterprise) }
    receiver    { FactoryGirl.create(:enterprise) }
    incoming    false
  end

  factory :variant_override, :class => VariantOverride do
    price         77.77
    count_on_hand 11111
  end

  factory :enterprise, :class => Enterprise do
    owner { FactoryGirl.create :user }
    sequence(:name) { |n| "Enterprise #{n}" }
    sells 'any'
    description 'enterprise'
    long_description '<p>Hello, world!</p><p>This is a paragraph.</p>'
    email 'enterprise@example.com'
    address { FactoryGirl.create(:address) }
    confirmed_at { Time.now }
  end

  factory :supplier_enterprise, :parent => :enterprise do
    is_primary_producer true
    sells "none"
  end

  factory :distributor_enterprise, :parent => :enterprise do
    is_primary_producer false
    sells "any"

    ignore do
      with_payment_and_shipping false
    end

    after(:create) do |enterprise, proxy|
      if proxy.with_payment_and_shipping
        create(:payment_method,  distributors: [enterprise])
        create(:shipping_method, distributors: [enterprise])
      end
    end
  end

  factory :enterprise_relationship do
  end

  factory :enterprise_role do
  end

  factory :enterprise_group, :class => EnterpriseGroup do
    name 'Enterprise group'
    sequence(:permalink) { |n| "group#{n}" }
    description 'this is a group'
    on_front_page false
    address { FactoryGirl.build(:address) }
  end

  sequence(:calculator_amount)
  factory :enterprise_fee, :class => EnterpriseFee do
    ignore { amount nil }

    sequence(:name) { |n| "Enterprise fee #{n}" }
    sequence(:fee_type) { |n| EnterpriseFee::FEE_TYPES[n % EnterpriseFee::FEE_TYPES.count] }

    enterprise { Enterprise.first || FactoryGirl.create(:supplier_enterprise) }
    calculator { Spree::Calculator::PerItem.new(preferred_amount: amount || generate(:calculator_amount)) }

    after(:create) { |ef| ef.calculator.save! }
  end

  factory :product_distribution, :class => ProductDistribution do
    product         { |pd| Spree::Product.first || FactoryGirl.create(:product) }
    distributor     { |pd| Enterprise.is_distributor.first || FactoryGirl.create(:distributor_enterprise) }
    enterprise_fee  { |pd| FactoryGirl.create(:enterprise_fee, enterprise: pd.distributor) }
  end

  factory :adjustment_metadata, :class => AdjustmentMetadata do
    adjustment { FactoryGirl.create(:adjustment) }
    enterprise { FactoryGirl.create(:distributor_enterprise) }
    fee_name 'fee'
    fee_type 'packing'
    enterprise_role 'distributor'
  end

  factory :weight_calculator, :class => OpenFoodNetwork::Calculator::Weight do
    after(:build)  { |c| c.set_preference(:per_kg, 0.5) }
    after(:create) { |c| c.set_preference(:per_kg, 0.5); c.save! }
  end

  factory :order_with_totals_and_distribution, :parent => :order do #possibly called :order_with_line_items in newer Spree
    distributor { create(:distributor_enterprise) }
    order_cycle { create(:simple_order_cycle) }

    after(:create) do |order|
      p = create(:simple_product, :distributors => [order.distributor])
      FactoryGirl.create(:line_item, :order => order, :product => p)
      order.reload
    end
  end

  factory :order_with_distributor, :parent => :order do
    distributor { create(:distributor_enterprise) }
  end

  factory :zone_with_member, :parent => :zone do
    default_tax true

    after(:create) do |zone|
      Spree::ZoneMember.create!(zone: zone, zoneable: Spree::Country.find_by_name('Australia'))
    end
  end

  factory :taxed_product, :parent => :product do
    ignore do
      tax_rate_amount 0
      zone nil
    end

    tax_category { create(:tax_category) }

    after(:create) do |product, proxy|
      raise "taxed_product factory requires a zone" unless proxy.zone
      create(:tax_rate, amount: proxy.tax_rate_amount, tax_category: product.tax_category, included_in_price: true, calculator: Spree::Calculator::DefaultTax.new, zone: proxy.zone)
    end
  end

  factory :customer, :class => Customer do
    email { Faker::Internet.email }
    enterprise
    code { SecureRandom.base64(150) }
    user
  end
end


FactoryGirl.modify do
  factory :base_product do
    unit_value 1
    unit_description ''
  end
  factory :product do
    primary_taxon { Spree::Taxon.first || FactoryGirl.create(:taxon) }
  end
  factory :simple_product do
    # Fix product factory name sequence with Kernel.rand so it is not interpreted as a Spree::Product method
    # Pull request: https://github.com/spree/spree/pull/1964
    # When this fix has been merged into a version of Spree that we're using, this line can be removed.
    sequence(:name) { |n| "Product ##{n} - #{Kernel.rand(9999)}" }

    supplier { Enterprise.is_primary_producer.first || FactoryGirl.create(:supplier_enterprise) }
    primary_taxon { Spree::Taxon.first || FactoryGirl.create(:taxon) }
    on_hand 3

    variant_unit 'weight'
    variant_unit_scale 1
    variant_unit_name ''
  end

  factory :base_variant do
    unit_value 1
    unit_description ''
  end

  factory :shipping_method do
    distributors { [Enterprise.is_distributor.first || FactoryGirl.create(:distributor_enterprise)] }
    display_on ''
  end

  factory :address do
    state { Spree::State.find_by_name 'Victoria' }
    country { Spree::Country.find_by_name 'Australia' || Spree::Country.first }
  end

  factory :payment do
    ignore do
      distributor { order.distributor || Enterprise.is_distributor.first || FactoryGirl.create(:distributor_enterprise) }
    end
    payment_method { FactoryGirl.create(:payment_method, distributors: [distributor]) }
  end

  factory :payment_method do
    distributors { [Enterprise.is_distributor.first || FactoryGirl.create(:distributor_enterprise)] }
  end

  factory :option_type do
    # Prevent inconsistent ordering in specs when all option types have the same (0) position
    sequence(:position)
  end

  factory :user do
    after(:create) do |user|
      user.spree_roles.clear # Remove admin role
    end
  end

  factory :admin_user do
    after(:create) do |user|
      user.spree_roles << Spree::Role.find_or_create_by_name!('admin')
    end
  end
end


# -- CMS
FactoryGirl.define do
  factory :cms_site, :class => Cms::Site do
    identifier 'open-food-network'
    label      'Open Food Network'
    hostname   'localhost'
  end

  factory :cms_layout, :class => Cms::Layout do
    site { Cms::Site.first || create(:cms_site) }
    label 'layout'
    identifier 'layout'
    content '{{ cms:page:content:text }}'
  end

  factory :cms_page, :class => Cms::Page do
    site { Cms::Site.first || create(:cms_site) }
    label 'page'
    sequence(:slug) { |n| "page-#{n}" }
    layout { Cms::Layout.first || create(:cms_layout) }

    # Pass content through to block, where it is stored
    after(:create) do |cms_page, evaluator|
      cms_page.blocks.first.update_attribute(:content, evaluator.content)
      cms_page.save! # set_cached_content
    end
  end

  factory :cms_block, :class => Cms::Block do
    page { Cms::Page.first || create(:cms_page) }
    identifier 'block'
    content 'hello, block'
  end
end
