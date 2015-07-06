require 'spec_helper'

feature "As a consumer I want to shop with a distributor", js: true do
  include AuthenticationWorkflow
  include WebHelper
  include ShopWorkflow
  include UIComponentHelper

  describe "Viewing a distributor" do

    let(:distributor) { create(:distributor_enterprise, with_payment_and_shipping: true) }
    let(:supplier) { create(:supplier_enterprise) }
    let(:oc1) { create(:simple_order_cycle, distributors: [distributor], coordinator: create(:distributor_enterprise), orders_close_at: 2.days.from_now) }
    let(:oc2) { create(:simple_order_cycle, distributors: [distributor], coordinator: create(:distributor_enterprise), orders_close_at: 3.days.from_now) }
    let(:product) { create(:simple_product, supplier: supplier) }
    let(:variant) { product.variants.first }
    let(:order) { create(:order, distributor: distributor) }

    before do
      set_order order
    end

    it "shows a distributor with images" do
      # Given the distributor has a logo
      distributor.logo = File.new(Rails.root + 'app/assets/images/logo-white.png')
      distributor.save!

      # Then we should see the distributor and its logo
      visit shop_path
      page.should have_text distributor.name
      find("#tab_about a").click
      first("distributor img")['src'].should == distributor.logo.url(:thumb)
    end

    it "shows the producers for a distributor" do
      exchange = Exchange.find(oc1.exchanges.to_enterprises(distributor).outgoing.first.id)
      exchange.variants << variant

      visit shop_path
      find("#tab_producers a").click
      page.should have_content supplier.name
    end

    describe "selecting an order cycle" do
      let(:exchange1) { Exchange.find(oc1.exchanges.to_enterprises(distributor).outgoing.first.id) }

      it "selects an order cycle if only one is open" do
        exchange1.update_attribute :pickup_time, "turtles"
        visit shop_path
        page.should have_selector "option[selected]", text: 'turtles'
      end

      describe "with multiple order cycles" do
        let(:exchange2) { Exchange.find(oc2.exchanges.to_enterprises(distributor).outgoing.first.id) }
        before do
          exchange1.update_attribute :pickup_time, "frogs"
          exchange2.update_attribute :pickup_time, "turtles"
        end

        it "shows a select with all order cycles, but doesn't show the products by default" do
          visit shop_path
          page.should have_selector "option", text: 'frogs'
          page.should have_selector "option", text: 'turtles'
          page.should_not have_selector("input.button.right", visible: true)
        end

        it "shows products after selecting an order cycle" do
          variant.update_attribute(:display_name, "kitten")
          variant.update_attribute(:display_as, "rabbit")
          exchange1.variants << variant ## add product to exchange
          visit shop_path
          page.should_not have_content product.name
          Spree::Order.last.order_cycle.should == nil

          select "frogs", :from => "order_cycle_id"
          page.should have_selector "products"
          page.should have_content "Next order closing in 2 days"
          Spree::Order.last.order_cycle.should == oc1
          page.should have_content product.name
          page.should have_content variant.display_name
          page.should have_content variant.display_as

          open_product_modal product
          modal_should_be_open_for product
        end
      end
    end

    describe "after selecting an order cycle with products visible" do
      let(:variant1) { create(:variant, product: product, price: 20) }
      let(:variant2) { create(:variant, product: product, price: 30) }
      let(:exchange) { Exchange.find(oc1.exchanges.to_enterprises(distributor).outgoing.first.id) }

      before do
        exchange.update_attribute :pickup_time, "frogs"
        exchange.variants << variant
        exchange.variants << variant1
        exchange.variants << variant2
        order.order_cycle = oc1
      end

      it "uses the adjusted price" do
        enterprise_fee1 = create(:enterprise_fee, amount: 20)
        enterprise_fee2 = create(:enterprise_fee, amount:  3)
        exchange.enterprise_fees = [enterprise_fee1, enterprise_fee2]
        exchange.save
        visit shop_path

        # Page should not have product.price (with or without fee)
        page.should_not have_price "$10.00"
        page.should_not have_price "$33.00"

        # Page should have variant prices (with fee)
        page.should have_price "$43.00"
        page.should have_price "$53.00"

        # Product price should be listed as the lesser of these
        page.should have_price "$43.00"
      end
    end

    describe "group buy products" do
      let(:exchange) { Exchange.find(oc1.exchanges.to_enterprises(distributor).outgoing.first.id) }
      let(:product) { create(:simple_product, group_buy: true, on_hand: 15) }
      let(:variant) { product.variants.first }
      let(:product2) { create(:simple_product, group_buy: false) }

      describe "with variants on the product" do
        let(:variant) { create(:variant, product: product, on_hand: 10 ) }
        before do
          add_product_and_variant_to_order_cycle(exchange, product, variant)
          set_order_cycle(order, oc1)
          visit shop_path
        end

        it "should save group buy data to the cart" do
          fill_in "variants[#{variant.id}]", with: 6
          fill_in "variant_attributes[#{variant.id}][max_quantity]", with: 7
          page.should have_in_cart product.name

          wait_until { !cart_dirty }

          li = Spree::Order.order(:created_at).last.line_items.order(:created_at).last
          li.max_quantity.should == 7
          li.quantity.should == 6
        end
      end
    end

    describe "adding products to cart" do
      let(:exchange) { Exchange.find(oc1.exchanges.to_enterprises(distributor).outgoing.first.id) }
      let(:product) { create(:simple_product) }
      let(:variant) { create(:variant, product: product) }
      before do
        add_product_and_variant_to_order_cycle(exchange, product, variant)
        set_order_cycle(order, oc1)
        visit shop_path
      end
      it "should let us add products to our cart" do
        fill_in "variants[#{variant.id}]", with: "1"
        page.should have_in_cart product.name
      end
    end

    context "when no order cycles are available" do
      it "tells us orders are closed" do
        visit shop_path
        page.should have_content "Orders are closed"
      end
      it "shows the last order cycle" do
        oc1 = create(:simple_order_cycle, distributors: [distributor], orders_close_at: 10.days.ago)
        visit shop_path
        page.should have_content "The last cycle closed 10 days ago"
      end
      it "shows the next order cycle" do
        oc1 = create(:simple_order_cycle, distributors: [distributor], orders_open_at: 10.days.from_now)
        visit shop_path
        page.should have_content "The next cycle opens in 10 days"
      end
    end
  end
end
