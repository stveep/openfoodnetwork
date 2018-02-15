require 'spec_helper'

describe ProxyOrder, type: :model do
  describe "cancel" do
    let(:order_cycle) { create(:simple_order_cycle) }
    let(:subscription) { create(:subscription) }

    context "when the order cycle is not yet closed" do
      let(:proxy_order) { create(:proxy_order, subscription: subscription, order: order, order_cycle: order_cycle) }
      before { order_cycle.update_attributes(orders_open_at: 1.day.ago, orders_close_at: 3.days.from_now) }

      context "and an order has not been initialised" do
        let(:order) { nil }

        it "returns true and sets canceled_at to the current time" do
          expect(proxy_order.cancel).to be true
          expect(proxy_order.reload.canceled_at).to be_within(5.seconds).of Time.zone.now
          expect(proxy_order.state).to eq 'canceled'
        end
      end

      context "and the order has already been completed" do
        let(:order) { create(:completed_order_with_totals) }

        it "returns true and sets canceled_at to the current time, and cancels the order" do
          expect(Spree::OrderMailer).to receive(:cancel_email) { double(:email, deliver: true) }
          expect(proxy_order.cancel).to be true
          expect(proxy_order.reload.canceled_at).to be_within(5.seconds).of Time.zone.now
          expect(order.reload.state).to eq 'canceled'
          expect(proxy_order.state).to eq 'canceled'
        end
      end

      context "and the order has not already been completed" do
        let(:order) { create(:order) }

        it "returns true and sets canceled_at to the current time" do
          expect(proxy_order.cancel).to be true
          expect(proxy_order.reload.canceled_at).to be_within(5.seconds).of Time.zone.now
          expect(order.reload.state).to eq 'cart'
          expect(proxy_order.state).to eq 'canceled'
        end
      end
    end

    context "when the order cycle is already closed" do
      let(:proxy_order) { create(:proxy_order, subscription: subscription, order: order, order_cycle: order_cycle) }
      before { order_cycle.update_attributes(orders_open_at: 3.days.ago, orders_close_at: 1.minute.ago) }

      context "and an order has not been initialised" do
        let(:order) { nil }

        it "returns false and does nothing" do
          expect(proxy_order.cancel).to be false
          expect(proxy_order.reload.canceled_at).to be nil
          expect(proxy_order.state).to eq 'pending'
        end
      end

      context "and an order has been initialised" do
        let(:order) { create(:order) }

        it "returns false and does nothing" do
          expect(proxy_order.cancel).to be false
          expect(proxy_order.reload.canceled_at).to be nil
          expect(order.reload.state).to eq 'cart'
          expect(proxy_order.state).to eq 'cart'
        end
      end
    end
  end

  describe "resume" do
    let!(:payment_method) { create(:payment_method) }
    let(:order) { create(:order_with_totals, shipping_method: create(:shipping_method)) }
    let(:proxy_order) { create(:proxy_order, order: order, canceled_at: Time.zone.now) }
    let(:order_cycle) { proxy_order.order_cycle }

    context "when the order cycle is not yet closed" do
      before { order_cycle.update_attributes(orders_open_at: 1.day.ago, orders_close_at: 3.days.from_now) }

      context "and the order has not been initialised" do
        let(:order) { nil }

        it "returns true and clears canceled_at" do
          expect(proxy_order.resume).to be true
          expect(proxy_order.reload.canceled_at).to be nil
          expect(proxy_order.state).to eq 'pending'
        end
      end

      context "and the order has already been cancelled" do
        before do
          allow(Spree::OrderMailer).to receive(:cancel_email) { double(:email, deliver: true) }
          while !order.completed? do break unless order.next! end
          order.cancel
        end

        it "returns true, clears canceled_at and resumes the order" do
          expect(proxy_order.resume).to be true
          expect(proxy_order.reload.canceled_at).to be nil
          expect(order.reload.state).to eq 'resumed'
          expect(proxy_order.state).to eq 'resumed'
        end
      end

      context "and the order has not been cancelled" do
        before { while !order.completed? do break unless order.next! end }

        it "returns true and clears canceled_at" do
          expect(proxy_order.resume).to be true
          expect(proxy_order.reload.canceled_at).to be nil
          expect(order.reload.state).to eq 'complete'
          expect(proxy_order.state).to eq 'cart'
        end
      end
    end

    context "when the order cycle is already closed" do
      before { order_cycle.update_attributes(orders_open_at: 3.days.ago, orders_close_at: 1.minute.ago) }

      context "and the order has not been initialised" do
        let(:order) { nil }

        it "returns false and does nothing" do
          expect(proxy_order.resume).to eq false
          expect(proxy_order.reload.canceled_at).to be_within(5.seconds).of Time.zone.now
          expect(proxy_order.state).to eq 'canceled'
        end
      end

      context "and the order has been cancelled" do
        before do
          allow(Spree::OrderMailer).to receive(:cancel_email) { double(:email, deliver: true) }
          while !order.completed? do break unless order.next! end
          order.cancel
        end

        it "returns false and does nothing" do
          expect(proxy_order.resume).to eq false
          expect(proxy_order.reload.canceled_at).to be_within(5.seconds).of Time.zone.now
          expect(order.reload.state).to eq 'canceled'
          expect(proxy_order.state).to eq 'canceled'
        end
      end

      context "and the order has not been cancelled" do
        before { while !order.completed? do break unless order.next! end }

        it "returns false and does nothing" do
          expect(proxy_order.resume).to eq false
          expect(proxy_order.reload.canceled_at).to be_within(5.seconds).of Time.zone.now
          expect(order.reload.state).to eq 'complete'
          expect(proxy_order.state).to eq 'canceled'
        end
      end
    end
  end

  describe "initialise_order!" do
    context "when the order has not already been initialised" do
      let(:subscription) { create(:subscription, with_items: true) }
      let!(:proxy_order) { create(:proxy_order, subscription: subscription) }

      it "builds a new order based the subscription" do
        expect{ proxy_order.initialise_order! }.to change{ Spree::Order.count }.by(1)
        expect(proxy_order.reload.order).to be_a Spree::Order
        order = proxy_order.order
        expect(order.line_items.count).to eq subscription.subscription_line_items.count
        expect(order.customer).to eq subscription.customer
        expect(order.user).to eq subscription.customer.user
        expect(order.distributor).to eq subscription.shop
        expect(order.order_cycle).to eq proxy_order.order_cycle
        expect(order.shipping_method).to eq subscription.shipping_method
        expect(order.shipments.first.shipping_method).to eq subscription.shipping_method
        expect(order.payments.first.payment_method).to eq subscription.payment_method
        expect(order.bill_address).to eq subscription.bill_address
        expect(order.ship_address).to eq subscription.ship_address
        expect(order.complete?).to be false
      end

      context "when a requested quantity is greater than available stock" do
        let(:sli) { subscription.subscription_line_items.first }
        let(:variant) { sli.variant }

        before do
          variant.update_attribute(:count_on_hand, 2)
          sli.update_attribute(:quantity, 5)
        end

        it "initialises the order with the requested quantity regardless" do
          expect{ proxy_order.initialise_order! }.to change{ Spree::Order.count }.by(1)
          expect(proxy_order.reload.order).to be_a Spree::Order
          order = proxy_order.order
          expect(order.line_items.find_by_variant_id(variant.id).quantity).to eq 5
        end
      end

      context "when the customer does not have a user associated with it" do
        before do
          subscription.customer.update_attribute(:user_id, nil)
        end

        it "initialises the order without a user_id" do
          expect{ proxy_order.initialise_order! }.to change{ Spree::Order.count }.by(1)
          expect(proxy_order.reload.order).to be_a Spree::Order
          order = proxy_order.order
          expect(order.user).to be nil
        end
      end
    end

    context "when the order has already been initialised" do
      let(:existing_order) { create(:order) }
      let!(:proxy_order) { create(:proxy_order, order: existing_order) }

      it "returns the existing order" do
        expect do
          expect(proxy_order.initialise_order!).to eq existing_order
        end.to_not change{ Spree::Order.count }
      end
    end
  end
end
