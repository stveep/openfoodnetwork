require 'csv'
require 'open_food_network/order_and_distributor_report'
require 'open_food_network/products_and_inventory_report'
require 'open_food_network/group_buy_report'
require 'open_food_network/order_grouper'
require 'open_food_network/customers_report'
require 'open_food_network/users_and_enterprises_report'
require 'open_food_network/order_cycle_management_report'
require 'open_food_network/sales_tax_report'
require 'open_food_network/xero_invoices_report'

Spree::Admin::ReportsController.class_eval do

  include Spree::ReportsHelper

  REPORT_TYPES = {
    orders_and_fulfillment: [
      ['Order Cycle Supplier Totals',:order_cycle_supplier_totals],
      ['Order Cycle Supplier Totals by Distributor',:order_cycle_supplier_totals_by_distributor],
      ['Order Cycle Distributor Totals by Supplier',:order_cycle_distributor_totals_by_supplier],
      ['Order Cycle Customer Totals',:order_cycle_customer_totals]
    ],
    products_and_inventory: [
      ['All products', :all_products],
      ['Inventory (on hand)', :inventory]
    ],
    customers: [
      ["Mailing List", :mailing_list],
      ["Addresses", :addresses]
    ],
    order_cycle_management: [
      ["Payment Methods Report", :payment_methods],
      ["Delivery Report", :delivery]
    ]
  }

  # Fetches user's distributors, suppliers and order_cycles
  before_filter :load_data, only: [:customers, :products_and_inventory, :order_cycle_management]

  # Render a partial for orders and fulfillment description
  respond_override :index => { :html => { :success => lambda {
    @reports[:orders_and_fulfillment][:description] =
      render_to_string(partial: 'orders_and_fulfillment_description', layout: false, locals: {report_types: REPORT_TYPES[:orders_and_fulfillment]}).html_safe
    @reports[:products_and_inventory][:description] =
      render_to_string(partial: 'products_and_inventory_description', layout: false, locals: {report_types: REPORT_TYPES[:products_and_inventory]}).html_safe
    @reports[:customers][:description] =
      render_to_string(partial: 'customers_description', layout: false, locals: {report_types: REPORT_TYPES[:customers]}).html_safe
    @reports[:order_cycle_management][:description] =
      render_to_string(partial: 'order_cycle_management_description', layout: false, locals: {report_types: REPORT_TYPES[:order_cycle_management]}).html_safe
  } } }


  # Overide spree reports list.
  def index
    @reports = authorized_reports
    respond_with(@reports)
  end

  # This action is short because we refactored it like bosses
  def customers
    @report_types = REPORT_TYPES[:customers]
    @report_type = params[:report_type]
    @report = OpenFoodNetwork::CustomersReport.new spree_current_user, params
    render_report(@report.header, @report.table, params[:csv], "customers_#{timestamp}.csv")
  end

  def order_cycle_management
    @report_types = REPORT_TYPES[:order_cycle_management]
    @report_type = params[:report_type]
    @report = OpenFoodNetwork::OrderCycleManagementReport.new spree_current_user, params

    @search = Spree::Order.complete.not_state(:canceled).managed_by(spree_current_user).search(params[:q])
    @orders = @search.result

    render_report(@report.header, @report.table, params[:csv], "order_cycle_management_#{timestamp}.csv")
  end

  def orders_and_distributors
    params[:q] ||= {}

    if params[:q][:completed_at_gt].blank?
      params[:q][:completed_at_gt] = Time.zone.now.beginning_of_month
    else
      params[:q][:completed_at_gt] = Time.zone.parse(params[:q][:completed_at_gt]).beginning_of_day rescue Time.zone.now.beginning_of_month
    end

    if params[:q] && !params[:q][:completed_at_lt].blank?
      params[:q][:completed_at_lt] = Time.zone.parse(params[:q][:completed_at_lt]).end_of_day rescue ""
    end
    params[:q][:meta_sort] ||= "completed_at.desc"

    @search = Spree::Order.complete.not_state(:canceled).managed_by(spree_current_user).search(params[:q])
    orders = @search.result

    @report = OpenFoodNetwork::OrderAndDistributorReport.new orders
    unless params[:csv]
      render :html => @report
    else
      csv_string = CSV.generate do |csv|
        csv << @report.header
        @report.table.each { |row| csv << row }
      end
      send_data csv_string, :filename => "orders_and_distributors_#{timestamp}.csv"
    end
  end

  def sales_tax
    params[:q] ||= {}

    if params[:q][:completed_at_gt].blank?
      params[:q][:completed_at_gt] = Time.zone.now.beginning_of_month
    else
      params[:q][:completed_at_gt] = Time.zone.parse(params[:q][:completed_at_gt]).beginning_of_day rescue Time.zone.now.beginning_of_month
    end

    if params[:q] && !params[:q][:completed_at_lt].blank?
      params[:q][:completed_at_lt] = Time.zone.parse(params[:q][:completed_at_lt]).end_of_day rescue ""
    end
    params[:q][:meta_sort] ||= "completed_at.desc"

    @search = Spree::Order.complete.not_state(:canceled).managed_by(spree_current_user).search(params[:q])
    orders = @search.result
    @distributors = Enterprise.is_distributor.managed_by(spree_current_user)

    @report = OpenFoodNetwork::SalesTaxReport.new orders
    unless params[:csv]
      render :html => @report
    else
      csv_string = CSV.generate do |csv|
        csv << @report.header
        @report.table.each { |row| csv << row }
      end
      send_data csv_string, :filename => "sales_tax.csv"
    end
  end

  def bulk_coop
    params[:q] ||= {}

    if params[:q][:completed_at_gt].blank?
      params[:q][:completed_at_gt] = Time.zone.now.beginning_of_month
    else
      params[:q][:completed_at_gt] = Time.zone.parse(params[:q][:completed_at_gt]).beginning_of_day rescue Time.zone.now.beginning_of_month
    end

    if params[:q] && !params[:q][:completed_at_lt].blank?
      params[:q][:completed_at_lt] = Time.zone.parse(params[:q][:completed_at_lt]).end_of_day rescue ""
    end
    params[:q][:meta_sort] ||= "completed_at.desc"

    @search = Spree::Order.complete.not_state(:canceled).managed_by(spree_current_user).search(params[:q])

    orders = @search.result
    @line_items = orders.map { |o| o.line_items.managed_by(spree_current_user) }.flatten

    @distributors = Enterprise.is_distributor.managed_by(spree_current_user)
    @report_type = params[:report_type]

    case params[:report_type]
    when "bulk_coop_supplier_report"

      header = ["Supplier", "Product", "Unit Size", "Variant", "Weight", "Sum Total", "Sum Max Total", "Units Required", "Remainder"]

      columns = [ proc { |lis| lis.first.variant.product.supplier.name },
        proc { |lis| lis.first.variant.product.name },
        proc { |lis| lis.first.variant.product.group_buy ? (lis.first.variant.product.group_buy_unit_size || 0.0) : "" },
        proc { |lis| lis.first.variant.full_name },
        proc { |lis| lis.first.variant.weight || 0 },
        proc { |lis|  lis.sum { |li| li.quantity } },
        proc { |lis| lis.sum { |li| li.max_quantity || 0 } },
        proc { |lis| "" },
        proc { |lis| "" } ]

      rules = [ { group_by: proc { |li| li.variant.product.supplier },
        sort_by: proc { |supplier| supplier.name } },
        { group_by: proc { |li| li.variant.product },
        sort_by: proc { |product| product.name },
        summary_columns: [ proc { |lis| lis.first.variant.product.supplier.name },
          proc { |lis| lis.first.variant.product.name },
          proc { |lis| lis.first.variant.product.group_buy ? (lis.first.variant.product.group_buy_unit_size || 0.0) : "" },
          proc { |lis| "" },
          proc { |lis| "" },
          proc { |lis| lis.sum { |li| (li.quantity || 0) * (li.variant.weight || 0) } },
          proc { |lis| lis.sum { |li| (li.max_quantity || 0) * (li.variant.weight || 0) } },
          proc { |lis| ( (lis.first.variant.product.group_buy_unit_size || 0).zero? ? 0 : ( lis.sum { |li| ( [li.max_quantity || 0, li.quantity || 0].max ) * (li.variant.weight || 0) } / lis.first.variant.product.group_buy_unit_size ) ).floor },
          proc { |lis| lis.sum { |li| ( [li.max_quantity || 0, li.quantity || 0].max) * (li.variant.weight || 0) } - ( ( (lis.first.variant.product.group_buy_unit_size || 0).zero? ? 0 : ( lis.sum { |li| ( [li.max_quantity || 0, li.quantity || 0].max) * (li.variant.weight || 0) } / lis.first.variant.product.group_buy_unit_size ) ).floor * (lis.first.variant.product.group_buy_unit_size || 0) ) } ] },
        { group_by: proc { |li| li.variant },
        sort_by: proc { |variant| variant.full_name } } ]

    when "bulk_coop_allocation"

      header = ["Customer", "Product", "Unit Size", "Variant", "Weight", "Sum Total", "Sum Max Total", "Total Allocated", "Remainder"]

      columns = [ proc { |lis| lis.first.order.bill_address.firstname + " " + lis.first.order.bill_address.lastname },
        proc { |lis| lis.first.variant.product.name },
        proc { |lis| lis.first.variant.product.group_buy ? (lis.first.variant.product.group_buy_unit_size || 0.0) : "" },
        proc { |lis| lis.first.variant.full_name },
        proc { |lis| lis.first.variant.weight || 0 },
        proc { |lis| lis.sum { |li| li.quantity } },
        proc { |lis| lis.sum { |li| li.max_quantity || 0 } },
        proc { |lis| "" },
        proc { |lis| "" } ]

      rules = [ { group_by: proc { |li| li.variant.product },
        sort_by: proc { |product| product.name },
        summary_columns: [ proc { |lis| "TOTAL" },
          proc { |lis| lis.first.variant.product.name },
          proc { |lis| lis.first.variant.product.group_buy ? (lis.first.variant.product.group_buy_unit_size || 0.0) : "" },
          proc { |lis| "" },
          proc { |lis| "" },
          proc { |lis| lis.sum { |li| li.quantity * (li.variant.weight || 0) } },
          proc { |lis| lis.sum { |li| (li.max_quantity || 0) * (li.variant.weight || 0) } },
          proc { |lis| ( (lis.first.variant.product.group_buy_unit_size || 0).zero? ? 0 : ( lis.sum { |li| ( [li.max_quantity || 0, li.quantity || 0].max ) * (li.variant.weight || 0) } / lis.first.variant.product.group_buy_unit_size ) ).floor * (lis.first.variant.product.group_buy_unit_size || 0) },
          proc { |lis| lis.sum { |li| ( [li.max_quantity || 0, li.quantity || 0].max ) * (li.variant.weight || 0) } - ( ( (lis.first.variant.product.group_buy_unit_size || 0).zero? ? 0 : ( lis.sum { |li| ( [li.max_quantity || 0, li.quantity || 0].max ) * (li.variant.weight || 0) } / lis.first.variant.product.group_buy_unit_size ) ).floor * (lis.first.variant.product.group_buy_unit_size || 0) ) } ] },
        { group_by: proc { |li| li.variant },
        sort_by: proc { |variant| variant.full_name } },
        { group_by: proc { |li| li.order },
        sort_by: proc { |order| order.to_s } } ]

    when "bulk_coop_packing_sheets"

      header = ["Customer", "Product", "Variant", "Sum Total"]

      columns = [ proc { |lis| lis.first.order.bill_address.firstname + " " + lis.first.order.bill_address.lastname },
        proc { |lis| lis.first.variant.product.name },
        proc { |lis| lis.first.variant.full_name },
        proc { |lis|  lis.sum { |li| li.quantity } } ]

      rules = [ { group_by: proc { |li| li.variant.product },
        sort_by: proc { |product| product.name } },
        { group_by: proc { |li| li.variant },
        sort_by: proc { |variant| variant.full_name } },
        { group_by: proc { |li| li.order },
        sort_by: proc { |order| order.to_s } } ]

    when "bulk_coop_customer_payments"

      header = ["Customer", "Date of Order", "Total Cost", "Amount Owing", "Amount Paid"]

      columns = [ proc { |lis| lis.first.order.bill_address.firstname + " " + lis.first.order.bill_address.lastname },
        proc { |lis| lis.first.order.completed_at.to_s },
        proc { |lis| lis.map { |li| li.order }.uniq.sum { |o| o.total } },
        proc { |lis| lis.map { |li| li.order }.uniq.sum { |o| o.outstanding_balance } },
        proc { |lis| lis.map { |li| li.order }.uniq.sum { |o| o.payment_total } } ]

      rules = [ { group_by: proc { |li| li.order },
        sort_by: proc { |order|  order.completed_at } } ]

    else # List all line items

      header = ["Supplier", "Product", "Unit Size", "Variant", "Weight", "Sum Total", "Sum Max Total", "Units Required", "Remainder"]

      columns = [ proc { |lis| lis.first.variant.product.supplier.name },
        proc { |lis| lis.first.variant.product.name },
        proc { |lis| lis.first.variant.product.group_buy ? (lis.first.variant.product.group_buy_unit_size || 0.0) : "" },
        proc { |lis| lis.first.variant.full_name },
        proc { |lis| lis.first.variant.weight || 0 },
        proc { |lis|  lis.sum { |li| li.quantity } },
        proc { |lis| lis.sum { |li| li.max_quantity || 0 } },
        proc { |lis| "" },
        proc { |lis| "" } ]

      rules = [ { group_by: proc { |li| li.variant.product.supplier },
        sort_by: proc { |supplier| supplier.name } },
        { group_by: proc { |li| li.variant.product },
        sort_by: proc { |product| product.name },
        summary_columns: [ proc { |lis| lis.first.variant.product.supplier.name },
          proc { |lis| lis.first.variant.product.name },
          proc { |lis| lis.first.variant.product.group_buy ? (lis.first.variant.product.group_buy_unit_size || 0.0) : "" },
          proc { |lis| "" },
          proc { |lis| "" },
          proc { |lis| lis.sum { |li| li.quantity * (li.variant.weight || 0) } },
          proc { |lis| lis.sum { |li| (li.max_quantity || 0) * (li.variant.weight || 0) } },
          proc { |lis| ( (lis.first.variant.product.group_buy_unit_size || 0).zero? ? 0 : ( lis.sum { |li| ( [li.max_quantity || 0, li.quantity || 0].max ) * (li.variant.weight || 0) } / lis.first.variant.product.group_buy_unit_size ) ).floor },
          proc { |lis| lis.sum { |li| ( [li.max_quantity || 0, li.quantity || 0].max ) * (li.variant.weight || 0) } - ( ( (lis.first.variant.product.group_buy_unit_size || 0).zero? ? 0 : ( lis.sum { |li| ( [li.max_quantity || 0, li.quantity || 0].max ) * (li.variant.weight || 0) } / lis.first.variant.product.group_buy_unit_size ) ).floor * (lis.first.variant.product.group_buy_unit_size || 0) ) } ] },
        { group_by: proc { |li| li.variant },
        sort_by: proc { |variant| variant.full_name } } ]

    end

    order_grouper = OpenFoodNetwork::OrderGrouper.new rules, columns

    @header = header
    @table = order_grouper.table(@line_items)
    csv_file_name = "bulk_coop_#{timestamp}.csv"

    render_report(@header, @table, params[:csv], csv_file_name)
  end

  def payments
    params[:q] ||= {}

    if params[:q][:completed_at_gt].blank?
      params[:q][:completed_at_gt] = Time.zone.now.beginning_of_month
    else
      params[:q][:completed_at_gt] = Time.zone.parse(params[:q][:completed_at_gt]).beginning_of_day rescue Time.zone.now.beginning_of_month
    end

    if params[:q] && !params[:q][:completed_at_lt].blank?
      params[:q][:completed_at_lt] = Time.zone.parse(params[:q][:completed_at_lt]).end_of_day rescue ""
    end
    params[:q][:meta_sort] ||= "completed_at.desc"

    @search = Spree::Order.complete.not_state(:canceled).managed_by(spree_current_user).search(params[:q])

    orders = @search.result
    payments = orders.map { |o| o.payments.select { |payment| payment.completed? } }.flatten # Only select completed payments

    @distributors = Enterprise.is_distributor.managed_by(spree_current_user)
    @report_type = params[:report_type]

    case params[:report_type]
    when "payments_by_payment_type"
      table_items = payments

      header = ["Payment State", "Distributor", "Payment Type", "Total (#{currency_symbol})"]

      columns = [ proc { |payments| payments.first.order.payment_state },
        proc { |payments| payments.first.order.distributor.name },
        proc { |payments| payments.first.payment_method.name },
        proc { |payments| payments.sum { |payment| payment.amount } } ]

      rules = [ { group_by: proc { |payment| payment.order.payment_state },
        sort_by: proc { |payment_state| payment_state } },
        { group_by: proc { |payment| payment.order.distributor },
        sort_by: proc { |distributor| distributor.name } },
        { group_by: proc { |payment| Spree::PaymentMethod.unscoped { payment.payment_method } },
        sort_by: proc { |method| method.name } } ]

    when "itemised_payment_totals"
      table_items = orders

      header = ["Payment State", "Distributor", "Product Total (#{currency_symbol})", "Shipping Total (#{currency_symbol})", "Outstanding Balance (#{currency_symbol})", "Total (#{currency_symbol})"]

      columns = [ proc { |orders| orders.first.payment_state },
        proc { |orders| orders.first.distributor.name },
        proc { |orders| orders.sum { |o| o.item_total } },
        proc { |orders| orders.sum { |o| o.ship_total } },
        proc { |orders| orders.sum { |o| o.outstanding_balance } },
        proc { |orders| orders.sum { |o| o.total } } ]

      rules = [ { group_by: proc { |order| order.payment_state },
        sort_by: proc { |payment_state| payment_state } },
        { group_by: proc { |order| order.distributor },
        sort_by: proc { |distributor| distributor.name } } ]

    when "payment_totals"
      table_items = orders

      header = ["Payment State", "Distributor", "Product Total (#{currency_symbol})", "Shipping Total (#{currency_symbol})", "Total (#{currency_symbol})", "EFT (#{currency_symbol})", "PayPal (#{currency_symbol})", "Outstanding Balance (#{currency_symbol})"]

      columns = [ proc { |orders| orders.first.payment_state },
        proc { |orders| orders.first.distributor.name },
        proc { |orders| orders.sum { |o| o.item_total } },
        proc { |orders| orders.sum { |o| o.ship_total } },
        proc { |orders| orders.sum { |o| o.total } },
        proc { |orders| orders.sum { |o| o.payments.select { |payment| payment.completed? && (payment.payment_method.name.to_s.include? "EFT") }.sum { |payment| payment.amount } } },
        proc { |orders| orders.sum { |o| o.payments.select { |payment| payment.completed? && (payment.payment_method.name.to_s.include? "PayPal") }.sum{ |payment| payment.amount } } },
        proc { |orders| orders.sum { |o| o.outstanding_balance } } ]

      rules = [ { group_by: proc { |order| order.payment_state },
        sort_by: proc { |payment_state| payment_state } },
        { group_by: proc { |order| order.distributor },
        sort_by: proc { |distributor| distributor.name } } ]

    else
      table_items = payments

      header = ["Payment State", "Distributor", "Payment Type", "Total (#{currency_symbol})"]

      columns = [ proc { |payments| payments.first.order.payment_state },
        proc { |payments| payments.first.order.distributor.name },
        proc { |payments| payments.first.payment_method.name },
        proc { |payments| payments.sum { |payment| payment.amount } } ]

      rules = [ { group_by: proc { |payment| payment.order.payment_state },
        sort_by: proc { |payment_state| payment_state } },
        { group_by: proc { |payment| payment.order.distributor },
        sort_by: proc { |distributor| distributor.name } },
        { group_by: proc { |payment| payment.payment_method },
        sort_by: proc { |method| method.name } } ]

    end

    order_grouper = OpenFoodNetwork::OrderGrouper.new rules, columns

    @header = header
    @table = order_grouper.table(table_items)
    csv_file_name = "payments_#{timestamp}.csv"

    render_report(@header, @table, params[:csv], csv_file_name)

  end

  def orders_and_fulfillment
    # -- Prepare parameters
    params[:q] ||= {}

    if params[:q][:completed_at_gt].blank?
      params[:q][:completed_at_gt] = Time.zone.now.beginning_of_month
    else
      params[:q][:completed_at_gt] = Time.zone.parse(params[:q][:completed_at_gt]) rescue Time.zone.now.beginning_of_month
    end

    if params[:q] && !params[:q][:completed_at_lt].blank?
      params[:q][:completed_at_lt] = Time.zone.parse(params[:q][:completed_at_lt]) rescue ""
    end
    params[:q][:meta_sort] ||= "completed_at.desc"

    permissions = OpenFoodNetwork::Permissions.new(spree_current_user)

    # -- Search

    @search = Spree::Order.complete.not_state(:canceled).search(params[:q])
    orders = permissions.visible_orders.merge(@search.result)

    @line_items = permissions.visible_line_items.merge(Spree::LineItem.where(order_id: orders))
    @line_items = @line_items.supplied_by_any(params[:supplier_id_in]) if params[:supplier_id_in].present?

    line_items_with_hidden_details = @line_items.where('"spree_line_items"."id" NOT IN (?)', permissions.editable_line_items)
    @line_items.select{ |li| line_items_with_hidden_details.include? li }.each do |line_item|
      # TODO We should really be hiding customer code here too, but until we
      # have an actual association between order and customer, it's a bit tricky
      line_item.order.bill_address.assign_attributes(firstname: "HIDDEN", lastname: "", phone: "", address1: "", address2: "", city: "", zipcode: "", state: nil)
      line_item.order.ship_address.assign_attributes(firstname: "HIDDEN", lastname: "", phone: "", address1: "", address2: "", city: "", zipcode: "", state: nil)
      line_item.order.assign_attributes(email: "HIDDEN")
    end

    # My distributors and any distributors distributing products I supply
    @distributors = permissions.visible_enterprises_for_order_reports.is_distributor

    # My suppliers and any suppliers supplying products I distribute
    @suppliers = permissions.visible_enterprises_for_order_reports.is_primary_producer

    @order_cycles = OrderCycle.active_or_complete.
    involving_managed_distributors_of(spree_current_user).order('orders_close_at DESC')

    @report_types = REPORT_TYPES[:orders_and_fulfillment]
    @report_type = params[:report_type]

    # -- Format according to report type
    case params[:report_type]
    when "order_cycle_supplier_totals"
      table_items = @line_items
      @include_blank = 'All'

      header = ["Producer", "Product", "Variant", "Amount", "Total Units", "Curr. Cost per Unit", "Total Cost", "Status", "Incoming Transport"]

      columns = [ proc { |line_items| line_items.first.variant.product.supplier.name },
        proc { |line_items| line_items.first.variant.product.name },
        proc { |line_items| line_items.first.variant.full_name },
        proc { |line_items| line_items.sum { |li| li.quantity } },
        proc { |line_items| total_units(line_items) },
        proc { |line_items| line_items.first.price },
        proc { |line_items| line_items.sum { |li| li.amount } },
        proc { |line_items| "" },
        proc { |line_items| "incoming transport" } ]

        rules = [ { group_by: proc { |line_item| line_item.variant.product.supplier },
          sort_by: proc { |supplier| supplier.name } },
          { group_by: proc { |line_item| line_item.variant.product },
          sort_by: proc { |product| product.name } },
          { group_by: proc { |line_item| line_item.variant },
          sort_by: proc { |variant| variant.full_name } } ]

    when "order_cycle_supplier_totals_by_distributor"
      table_items = @line_items
      @include_blank = 'All'

      header = ["Producer", "Product", "Variant", "To Hub", "Amount", "Curr. Cost per Unit", "Total Cost", "Shipping Method"]

      columns = [ proc { |line_items| line_items.first.variant.product.supplier.name },
        proc { |line_items| line_items.first.variant.product.name },
        proc { |line_items| line_items.first.variant.full_name },
        proc { |line_items| line_items.first.order.distributor.name },
        proc { |line_items| line_items.sum { |li| li.quantity } },
        proc { |line_items| line_items.first.price },
        proc { |line_items| line_items.sum { |li| li.amount } },
        proc { |line_items| "shipping method" } ]

      rules = [ { group_by: proc { |line_item| line_item.variant.product.supplier },
        sort_by: proc { |supplier| supplier.name } },
        { group_by: proc { |line_item| line_item.variant.product },
        sort_by: proc { |product| product.name } },
        { group_by: proc { |line_item| line_item.variant },
        sort_by: proc { |variant| variant.full_name },
        summary_columns: [ proc { |line_items| "" },
          proc { |line_items| "" },
          proc { |line_items| "" },
          proc { |line_items| "TOTAL" },
          proc { |line_items| "" },
          proc { |line_items| "" },
          proc { |line_items| line_items.sum { |li| li.amount } },
          proc { |line_items| "" } ] },
        { group_by: proc { |line_item| line_item.order.distributor },
        sort_by: proc { |distributor| distributor.name } } ]

    when "order_cycle_distributor_totals_by_supplier"
      table_items = @line_items
      @include_blank = 'All'

      header = ["Hub", "Producer", "Product", "Variant", "Amount", "Curr. Cost per Unit", "Total Cost", "Total Shipping Cost", "Shipping Method"]

      columns = [ proc { |line_items| line_items.first.order.distributor.name },
        proc { |line_items| line_items.first.variant.product.supplier.name },
        proc { |line_items| line_items.first.variant.product.name },
        proc { |line_items| line_items.first.variant.full_name },
        proc { |line_items| line_items.sum { |li| li.quantity } },
        proc { |line_items| line_items.first.price },
        proc { |line_items| line_items.sum { |li| li.amount } },
        proc { |line_items| "" },
        proc { |line_items| "shipping method" } ]

      rules = [ { group_by: proc { |line_item| line_item.order.distributor },
        sort_by: proc { |distributor| distributor.name },
        summary_columns: [ proc { |line_items| "" },
          proc { |line_items| "TOTAL" },
          proc { |line_items| "" },
          proc { |line_items| "" },
          proc { |line_items| "" },
          proc { |line_items| "" },
          proc { |line_items| line_items.sum { |li| li.amount } },
          proc { |line_items| line_items.map { |li| li.order }.uniq.sum { |o| o.ship_total } },
          proc { |line_items| "" } ] },
        { group_by: proc { |line_item| line_item.variant.product.supplier },
        sort_by: proc { |supplier| supplier.name } },
        { group_by: proc { |line_item| line_item.variant.product },
        sort_by: proc { |product| product.name } },
        { group_by: proc { |line_item| line_item.variant },
        sort_by: proc { |variant| variant.full_name } } ]

    when "order_cycle_customer_totals"
      table_items = @line_items
      @include_blank = 'All'

      header = ["Hub", "Customer", "Email", "Phone", "Producer", "Product", "Variant",
                "Amount", "Item (#{currency_symbol})", "Item + Fees (#{currency_symbol})", "Admin & Handling (#{currency_symbol})", "Ship (#{currency_symbol})", "Total (#{currency_symbol})", "Paid?",
                "Shipping", "Delivery?",
                "Ship Street", "Ship Street 2", "Ship City", "Ship Postcode", "Ship State",
                "Comments", "SKU",
                "Order Cycle", "Payment Method", "Customer Code", "Tags",
                "Billing Street 1", "Billing Street 2", "Billing City", "Billing Postcode", "Billing State"
               ]

      rsa = proc { |line_items| line_items.first.order.shipping_method.andand.require_ship_address }

      columns = [
        proc { |line_items| line_items.first.order.distributor.name },
        proc { |line_items| line_items.first.order.bill_address.firstname + " " + line_items.first.order.bill_address.lastname },
        proc { |line_items| line_items.first.order.email },
        proc { |line_items| line_items.first.order.bill_address.phone },
        proc { |line_items| line_items.first.variant.product.supplier.name },
        proc { |line_items| line_items.first.variant.product.name },
        proc { |line_items| line_items.first.variant.full_name },

        proc { |line_items| line_items.sum { |li| li.quantity } },
        proc { |line_items| line_items.sum { |li| li.amount } },
        proc { |line_items| line_items.sum { |li| li.amount_with_adjustments } },
        proc { |line_items| "" },
        proc { |line_items| "" },
        proc { |line_items| "" },
        proc { |line_items| "" },

        proc { |line_items| line_items.first.order.shipping_method.andand.name },
        proc { |line_items| rsa.call(line_items) ? 'Y' : 'N' },

        proc { |line_items| line_items.first.order.ship_address.andand.address1 if rsa.call(line_items) },
        proc { |line_items| line_items.first.order.ship_address.andand.address2 if rsa.call(line_items) },
        proc { |line_items| line_items.first.order.ship_address.andand.city if rsa.call(line_items) },
        proc { |line_items| line_items.first.order.ship_address.andand.zipcode if rsa.call(line_items) },
        proc { |line_items| line_items.first.order.ship_address.andand.state if rsa.call(line_items) },

        proc { |line_items| "" },
        proc { |line_items| line_items.first.variant.product.sku },

        proc { |line_items| line_items.first.order.order_cycle.andand.name },
        proc { |line_items| line_items.first.order.payments.first.andand.payment_method.andand.name },
        proc { |line_items| line_items.first.order.user.andand.customer_of(line_items.first.order.distributor).andand.code },
        proc { |line_items| "" },

        proc { |line_items| line_items.first.order.bill_address.andand.address1 },
        proc { |line_items| line_items.first.order.bill_address.andand.address2 },
        proc { |line_items| line_items.first.order.bill_address.andand.city },
        proc { |line_items| line_items.first.order.bill_address.andand.zipcode },
        proc { |line_items| line_items.first.order.bill_address.andand.state } ]

    rules = [ { group_by: proc { |line_item| line_item.order.distributor },
      sort_by: proc { |distributor| distributor.name } },
      { group_by: proc { |line_item| line_item.order },
      sort_by: proc { |order| order.bill_address.lastname + " " + order.bill_address.firstname },
      summary_columns: [
        proc { |line_items| line_items.first.order.distributor.name },
        proc { |line_items| line_items.first.order.bill_address.firstname + " " + line_items.first.order.bill_address.lastname },
        proc { |line_items| "" },
        proc { |line_items| "" },
        proc { |line_items| "" },
        proc { |line_items| "TOTAL" },
        proc { |line_items| "" },

        proc { |line_items| "" },
        proc { |line_items| line_items.sum { |li| li.amount } },
        proc { |line_items| line_items.sum { |li| li.amount_with_adjustments } },
        proc { |line_items| line_items.map { |li| li.order }.uniq.sum { |o| o.admin_and_handling_total } },
        proc { |line_items| line_items.map { |li| li.order }.uniq.sum { |o| o.ship_total } },
        proc { |line_items| line_items.map { |li| li.order }.uniq.sum { |o| o.total } },
        proc { |line_items| line_items.all? { |li| li.order.paid? } ? "Yes" : "No" },

        proc { |line_items| "" },
        proc { |line_items| "" },

        proc { |line_items| "" },
        proc { |line_items| "" },
        proc { |line_items| "" },
        proc { |line_items| "" },
        proc { |line_items| "" },

        proc { |line_items| line_items.first.order.special_instructions } ,
        proc { |line_items| "" },

        proc { |line_items| line_items.first.order.order_cycle.andand.name },
        proc { |line_items| line_items.first.order.payments.first.andand.payment_method.andand.name },
        proc { |line_items| "" },
        proc { |line_items| "" },

        proc { |line_items| "" },
        proc { |line_items| "" },
        proc { |line_items| "" },
        proc { |line_items| "" },
        proc { |line_items| "" }
      ] },

      { group_by: proc { |line_item| line_item.variant.product },
      sort_by: proc { |product| product.name } },
      { group_by: proc { |line_item| line_item.variant },
       sort_by: proc { |variant| variant.full_name } } ]

    else
      table_items = @line_items
      @include_blank = 'All'

      header = ["Producer", "Product", "Variant", "Amount", "Curr. Cost per Unit", "Total Cost", "Status", "Incoming Transport"]

      columns = [ proc { |line_items| line_items.first.variant.product.supplier.name },
        proc { |line_items| line_items.first.variant.product.name },
        proc { |line_items| line_items.first.variant.full_name },
        proc { |line_items| line_items.sum { |li| li.quantity } },
        proc { |line_items| line_items.first.price },
        proc { |line_items| line_items.sum { |li| li.quantity * li.price } },
        proc { |line_items| "" },
        proc { |line_items| "incoming transport" } ]

      rules = [ { group_by: proc { |line_item| line_item.variant.product.supplier },
        sort_by: proc { |supplier| supplier.name } },
        { group_by: proc { |line_item| line_item.variant.product },
        sort_by: proc { |product| product.name } },
        { group_by: proc { |line_item| line_item.variant },
        sort_by: proc { |variant| variant.full_name } } ]

    end

    order_grouper = OpenFoodNetwork::OrderGrouper.new rules, columns

    @header = header
    @table = order_grouper.table(table_items)
    csv_file_name = "#{params[:report_type]}_#{timestamp}.csv"

    render_report(@header, @table, params[:csv], csv_file_name)

  end

  def products_and_inventory
    @report_types = REPORT_TYPES[:products_and_inventory]
    @report = OpenFoodNetwork::ProductsAndInventoryReport.new spree_current_user, params
    render_report(@report.header, @report.table, params[:csv], "products_and_inventory_#{timestamp}.csv")
  end

  def users_and_enterprises
    # @report_types = REPORT_TYPES[:users_and_enterprises]
    @report = OpenFoodNetwork::UsersAndEnterprisesReport.new params
    render_report(@report.header, @report.table, params[:csv], "users_and_enterprises_#{timestamp}.csv")
  end

  def xero_invoices
    if request.get?
      params[:q] ||= {}
      params[:q][:completed_at_gt] = Time.zone.now.beginning_of_month
    end
    @distributors = Enterprise.is_distributor.managed_by(spree_current_user)
    @order_cycles = OrderCycle.active_or_complete.accessible_by(spree_current_user).order('orders_close_at DESC')

    @search = Spree::Order.complete.managed_by(spree_current_user).order('id DESC').search(params[:q])
    orders = @search.result
    @report = OpenFoodNetwork::XeroInvoicesReport.new orders, params
    render_report(@report.header, @report.table, params[:csv], "xero_invoices_#{timestamp}.csv")
  end


  def render_report(header, table, create_csv, csv_file_name)
    unless create_csv
      render :html => table
    else
      csv_string = CSV.generate do |csv|
        csv << header
       table.each { |row| csv << row }
      end
      send_data csv_string, :filename => csv_file_name
    end
  end

  private

  def load_data
    # Load distributors either owned by the user or selling their enterprises products.
    my_distributors = Enterprise.is_distributor.managed_by(spree_current_user)
    my_suppliers = Enterprise.is_primary_producer.managed_by(spree_current_user)
    distributors_of_my_products = Enterprise.with_distributed_products_outer.merge(Spree::Product.in_any_supplier(my_suppliers))
    @distributors = my_distributors | distributors_of_my_products
    # Load suppliers either owned by the user or supplying products their enterprises distribute.
    suppliers_of_products_I_distribute = my_distributors.map { |d| Spree::Product.in_distributor(d) }.flatten.map(&:supplier).uniq
    @suppliers = my_suppliers | suppliers_of_products_I_distribute
    @order_cycles = OrderCycle.active_or_complete.accessible_by(spree_current_user).order('orders_close_at DESC')
  end

  def authorized_reports
    reports = {
      :orders_and_distributors => {:name => "Orders And Distributors", :description => "Orders with distributor details"},
      :bulk_coop => {:name => "Bulk Co-Op", :description => "Reports for Bulk Co-Op orders"},
      :payments => {:name => "Payment Reports", :description => "Reports for Payments"},
      :orders_and_fulfillment => {:name => "Orders & Fulfillment Reports", :description => ''},
      :customers => {:name => "Customers", :description => 'Customer details'},
      :products_and_inventory => {:name => "Products & Inventory", :description => ''},
      :sales_total => { :name => "Sales Total", :description => "Sales Total For All Orders" },
      :users_and_enterprises => { :name => "Users & Enterprises", :description => "Enterprise Ownership & Status" },
      :order_cycle_management => {:name => "Order Cycle Management", :description => ''},
      :sales_tax => { :name => "Sales Tax", :description => "Sales Tax For Orders" },
      :xero_invoices => { :name => "Xero Invoices", :description => 'Invoices for import into Xero' }

    }
    # Return only reports the user is authorized to view.
    reports.select { |action| can? action, :report }
  end

  def total_units(line_items)
    return " " if line_items.map{ |li| li.variant.unit_value.nil? }.any?
    total_units = line_items.sum do |li|
      scale_factor = ( li.product.variant_unit == 'weight' ? 1000 : 1 )
      li.quantity * li.variant.unit_value / scale_factor
    end
    total_units.round(3)
  end

  def timestamp
    Time.now.strftime("%Y%m%d")
  end
end
