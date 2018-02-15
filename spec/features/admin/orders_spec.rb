require "spec_helper"

feature %q{
    As an administrator
    I want to manage orders
}, js: true do
  include AuthenticationWorkflow
  include WebHelper
  include CheckoutHelper

  background do
    @user = create(:user)
    @product = create(:simple_product)
    @distributor = create(:distributor_enterprise, owner: @user, charges_sales_tax: true)
    @order_cycle = create(:simple_order_cycle, name: 'One', distributors: [@distributor], variants: [@product.variants.first])

    @order = create(:order_with_totals_and_distribution, user: @user, distributor: @distributor, order_cycle: @order_cycle, state: 'complete', payment_state: 'balance_due')
    @customer = create(:customer, enterprise: @distributor, email: @user.email, user: @user, ship_address: create(:address))

    # ensure order has a payment to capture
    @order.finalize!

    create :check_payment, order: @order, amount: @order.total
  end

  def new_order_with_distribution(distributor, order_cycle)
    visit 'admin/orders/new'
    expect(page).to have_selector('#s2id_order_distributor_id')
    select2_select distributor.name, from: 'order_distributor_id'
    select2_select order_cycle.name, from: 'order_order_cycle_id'
    click_button 'Next'
  end

  scenario "creating an order with distributor and order cycle" do
    distributor_disabled = create(:distributor_enterprise)
    create(:simple_order_cycle, name: 'Two')

    login_to_admin_section

    visit '/admin/orders'
    click_link 'New Order'

    # Distributors without an order cycle should be shown as disabled
    open_select2('#s2id_order_distributor_id')
    page.should have_selector "ul.select2-results li.select2-result.select2-disabled", text: distributor_disabled.name
    close_select2('#s2id_order_distributor_id')

    # Order cycle selector should be disabled
    page.should have_selector "#s2id_order_order_cycle_id.select2-container-disabled"

    # When we select a distributor, it should limit order cycle selection to those for that distributor
    select2_select @distributor.name, from: 'order_distributor_id'
    page.should have_select2 'order_order_cycle_id', options: ['One (open)']
    select2_select @order_cycle.name, from: 'order_order_cycle_id'
    click_button 'Next'

    # it suppresses validation errors when setting distribution
    page.should_not have_selector '#errorExplanation'
    page.should have_content 'ADD PRODUCT'
    targetted_select2_search @product.name, from: '#add_variant_id', dropdown_css: '.select2-drop'
    click_link 'Add'
    page.has_selector? "table.index tbody[data-hook='admin_order_form_line_items'] tr"  # Wait for JS
    page.should have_selector 'td', text: @product.name

    click_button 'Update'

    page.should have_selector 'h1', text: 'Customer Details'
    o = Spree::Order.last
    o.distributor.should == @distributor
    o.order_cycle.should == @order_cycle
  end

  scenario "can add a product to an existing order", retry: 3 do
    login_to_admin_section
    visit '/admin/orders'

    click_edit

    targetted_select2_search @product.name, from: '#add_variant_id', dropdown_css: '.select2-drop'

    click_link 'Add'

    page.should have_selector 'td', text: @product.name
    @order.line_items(true).map(&:product).should include @product
  end

  scenario "displays error when incorrect distribution for products is chosen" do
    d = create(:distributor_enterprise)
    oc = create(:simple_order_cycle, distributors: [d])
    puts d.name
    puts @distributor.name

    @order.state = 'cart'; @order.completed_at = nil; @order.save

    login_to_admin_section
    visit '/admin/orders'
    uncheck 'Only show complete orders'
    click_button 'Filter Results'

    click_edit

    select2_select d.name, from: 'order_distributor_id'
    select2_select oc.name, from: 'order_order_cycle_id'

    click_button 'Update And Recalculate Fees'
    page.should have_content "Distributor or order cycle cannot supply the products in your cart"
  end


  scenario "can't add products to an order outside the order's hub and order cycle" do
    product = create(:simple_product)

    login_to_admin_section
    visit '/admin/orders'
    page.find('td.actions a.icon-edit').click

    page.should_not have_select2_option product.name, from: ".variant_autocomplete", dropdown_css: ".select2-search"
  end

  scenario "can't change distributor or order cycle once order has been finalized" do
    @order.update_attributes order_cycle_id: nil

    login_to_admin_section
    visit '/admin/orders'
    page.find('td.actions a.icon-edit').click

    page.should_not have_select2 'order_distributor_id'
    page.should_not have_select2 'order_order_cycle_id'

    page.should have_selector 'p', text: "Distributor: #{@order.distributor.name}"
    page.should have_selector 'p', text: "Order cycle: None"
  end

  scenario "filling customer details" do
    # Given a customer with an order, which includes their shipping and billing address
    @order.ship_address = create(:address, lastname: 'Ship')
    @order.bill_address = create(:address, lastname: 'Bill')
    @order.shipping_method = create(:shipping_method, require_ship_address: true)
    @order.save!

    # When I create a new order
    quick_login_as @user
    new_order_with_distribution(@distributor, @order_cycle)
    targetted_select2_search @product.name, from: '#add_variant_id', dropdown_css: '.select2-drop'
    click_link 'Add'
    page.has_selector? "table.index tbody[data-hook='admin_order_form_line_items'] tr"  # Wait for JS
    click_button 'Update'
    expect(page).to have_selector 'h1.page-title', text: "Customer Details"

    # And I select that customer's email address and save the order
    targetted_select2_search @customer.email, from: '#customer_search_override', dropdown_css: '.select2-drop'
    click_button 'Continue'
    expect(page).to have_selector "h1.page-title", text: "Shipments"

    # Then their addresses should be associated with the order
    order = Spree::Order.last
    expect(order.ship_address.lastname).to eq @customer.ship_address.lastname
    expect(order.bill_address.lastname).to eq @customer.bill_address.lastname
  end

  scenario "capture payment from the orders index page" do
    login_to_admin_section

    visit spree.admin_orders_path
    expect(page).to have_current_path spree.admin_orders_path

    # click the 'capture' link for the order
    page.find("[data-action=capture][href*=#{@order.number}]").click

    expect(page).to have_content "Payment Updated"

    # check the order was captured
    expect(@order.reload.payment_state).to eq "paid"

    # we should still be on the same page
    expect(page).to have_current_path spree.admin_orders_path
  end

  context "as an enterprise manager" do
    let(:coordinator1) { create(:distributor_enterprise) }
    let(:coordinator2) { create(:distributor_enterprise) }
    let!(:order_cycle1) { create(:order_cycle, coordinator: coordinator1) }
    let!(:order_cycle2) { create(:simple_order_cycle, coordinator: coordinator2) }
    let!(:supplier1) { order_cycle1.suppliers.first }
    let!(:supplier2) { order_cycle1.suppliers.last }
    let!(:distributor1) { order_cycle1.distributors.first }
    let!(:distributor2) { order_cycle1.distributors.reject{ |d| d == distributor1 }.last } # ensure d1 != d2
    let(:product) { order_cycle1.products.first }

    before(:each) do
      @enterprise_user = create_enterprise_user
      @enterprise_user.enterprise_roles.build(enterprise: supplier1).save
      @enterprise_user.enterprise_roles.build(enterprise: coordinator1).save
      @enterprise_user.enterprise_roles.build(enterprise: distributor1).save

      login_to_admin_as @enterprise_user
    end

    feature "viewing the edit page" do
      background do
        Spree::Config[:enable_receipt_printing?] = true

        distributor1.update_attribute(:abn, '12345678')
        @order = create(:completed_order_with_totals, distributor: distributor1)

        visit spree.admin_order_path(@order)
      end

      scenario "shows the dropdown menu" do
        find("#links-dropdown .ofn-drop-down").click
        within "#links-dropdown" do
          expect(page).to have_link "Edit", href: spree.edit_admin_order_path(@order)
          expect(page).to have_link "Resend Confirmation", href: spree.resend_admin_order_path(@order)
          expect(page).to have_link "Send Invoice", href: spree.invoice_admin_order_path(@order)
          expect(page).to have_link "Print Invoice", href: spree.print_admin_order_path(@order)
          # expect(page).to have_link "Ship Order", href: spree.fire_admin_order_path(@order, :e => 'ship')
          expect(page).to have_link "Cancel Order", href: spree.fire_admin_order_path(@order, :e => 'cancel')
        end
      end

      scenario "can print an order's ticket" do
        find("#links-dropdown .ofn-drop-down").click

        ticket_window = window_opened_by do
          within('#links-dropdown') do
            click_link('Print Ticket')
          end
        end

        within_window ticket_window do
          print_data = page.evaluate_script('printData');
          elements_in_print_data =
            [
              @order.distributor.name,
              @order.distributor.address.address_part1,
              @order.distributor.address.address_part2,
              @order.distributor.contact.email,
              @order.number,
              @order.line_items.map { |line_item|
                [line_item.quantity.to_s,
                 line_item.product.name,
                 line_item.single_display_amount_with_adjustments.format(symbol: false, with_currency: false),
                 line_item.display_amount_with_adjustments.format(symbol: false, with_currency: false)]
              },
              checkout_adjustments_for(@order, exclude: [:line_item]).reject { |a| a.amount == 0 }.map { |adjustment|
                [raw(adjustment.label),
                 display_adjustment_amount(adjustment).format(symbol: false, with_currency: false)]
              },
              @order.display_total.format(with_currency: false),
              display_checkout_taxes_hash(@order).map { |tax_rate, tax_value|
                [tax_rate,
                 tax_value.format(with_currency: false)]
              },
              display_checkout_total_less_tax(@order).format(with_currency: false)
            ]
          expect(print_data.join).to include(*elements_in_print_data.flatten)
        end
      end
    end

    scenario "creating an order with distributor and order cycle" do
      new_order_with_distribution(distributor1, order_cycle1)

      expect(page).to have_content 'ADD PRODUCT'
      targetted_select2_search product.name, from: '#add_variant_id', dropdown_css: '.select2-drop'

      click_link 'Add'
      page.has_selector? "table.index tbody[data-hook='admin_order_form_line_items'] tr"  # Wait for JS
      expect(page).to have_selector 'td', text: product.name

      expect(page).to have_select2 'order_distributor_id', with_options: [distributor1.name]
      expect(page).to_not have_select2 'order_distributor_id', with_options: [distributor2.name]

      expect(page).to have_select2 'order_order_cycle_id', with_options: ["#{order_cycle1.name} (open)"]
      expect(page).to_not have_select2 'order_order_cycle_id', with_options: ["#{order_cycle2.name} (open)"]

      click_button 'Update'

      expect(page).to have_selector 'h1', text: 'Customer Details'
      o = Spree::Order.last
      expect(o.distributor).to eq distributor1
      expect(o.order_cycle).to eq order_cycle1
    end

  end


  # Working around intermittent click failing
  # Possible causes of failure:
  #  - the link moves
  #  - the missing content (font icon only)
  #  - the screen is not big enough
  # However, some operations before the click or a second click on failure work.
  #
  # A lot of people had similar problems:
  # https://github.com/teampoltergeist/poltergeist/issues/520
  # https://github.com/thoughtbot/capybara-webkit/issues/494
  def click_edit
    click_result = click_icon :edit
    unless click_result['status'] == 'success'
      click_icon :edit
    end
  end
end
