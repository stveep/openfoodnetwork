require 'spec_helper'

describe SubscriptionConfirmJob do
  let(:job) { SubscriptionConfirmJob.new }

  describe "finding proxy_orders that are ready to be confirmed" do
    let(:shop) { create(:distributor_enterprise) }
    let(:order_cycle1) { create(:simple_order_cycle, coordinator: shop, orders_close_at: 59.minutes.ago, updated_at: 1.day.ago) }
    let(:order_cycle2) { create(:simple_order_cycle, coordinator: shop, orders_close_at: 61.minutes.ago, updated_at: 1.day.ago) }
    let(:schedule) { create(:schedule, order_cycles: [order_cycle1, order_cycle2]) }
    let(:subscription) { create(:subscription, shop: shop, schedule: schedule) }
    let!(:proxy_order) { create(:proxy_order, subscription: subscription, order_cycle: order_cycle1, placed_at: 5.minutes.ago, order: create(:order, completed_at: 1.minute.ago)) }
    let(:proxy_orders) { job.send(:proxy_orders) }

    it "returns proxy orders that meet all of the criteria" do
      expect(proxy_orders).to include proxy_order
    end

    it "ignores proxy orders where the OC closed more than 1 hour ago" do
      proxy_order.update_attributes!(order_cycle_id: order_cycle2.id)
      expect(proxy_orders).to_not include proxy_order
    end

    it "ignores proxy orders for paused subscriptions" do
      subscription.update_attributes!(paused_at: 1.minute.ago)
      expect(proxy_orders).to_not include proxy_order
    end

    it "ignores proxy orders for cancelled subscriptions" do
      subscription.update_attributes!(canceled_at: 1.minute.ago)
      expect(proxy_orders).to_not include proxy_order
    end

    it "ignores cancelled proxy orders" do
      proxy_order.update_attributes!(canceled_at: 5.minutes.ago)
      expect(proxy_orders).to_not include proxy_order
    end

    it "ignores proxy orders without a completed order" do
      proxy_order.order.completed_at = nil
      proxy_order.order.save!
      expect(proxy_orders).to_not include proxy_order
    end

    it "ignores proxy orders without an associated order" do
      proxy_order.update_attributes!(order_id: nil)
      expect(proxy_orders).to_not include proxy_order
    end

    it "ignores proxy orders that haven't been placed yet" do
      proxy_order.update_attributes!(placed_at: nil)
      expect(proxy_orders).to_not include proxy_order
    end

    it "ignores proxy orders that have already been confirmed" do
      proxy_order.update_attributes!(confirmed_at: 1.second.ago)
      expect(proxy_orders).to_not include proxy_order
    end
  end

  describe "performing the job" do
    context "when unconfirmed proxy_orders exist" do
      let!(:proxy_order) { create(:proxy_order) }

      before do
        proxy_order.initialise_order!
        allow(job).to receive(:proxy_orders) { ProxyOrder.where(id: proxy_order.id) }
        allow(job).to receive(:process!)
        allow(job).to receive(:send_confirmation_summary_emails)
      end

      it "marks confirmable proxy_orders as processed by setting confirmed_at" do
        expect{ job.perform }.to change{ proxy_order.reload.confirmed_at }
        expect(proxy_order.confirmed_at).to be_within(5.seconds).of Time.zone.now
      end

      it "processes confirmable proxy_orders" do
        job.perform
        expect(job).to have_received(:process!)
        expect(job.instance_variable_get(:@order)).to eq proxy_order.reload.order
      end

      it "sends a summary email" do
        job.perform
        expect(job).to have_received(:send_confirmation_summary_emails)
      end
    end
  end

  describe "finding recently closed order cycles" do
    let!(:order_cycle1) { create(:simple_order_cycle, orders_close_at: 61.minutes.ago, updated_at: 61.minutes.ago) }
    let!(:order_cycle2) { create(:simple_order_cycle, orders_close_at: nil, updated_at: 59.minutes.ago) }
    let!(:order_cycle3) { create(:simple_order_cycle, orders_close_at: 61.minutes.ago, updated_at: 59.minutes.ago) }
    let!(:order_cycle4) { create(:simple_order_cycle, orders_close_at: 59.minutes.ago, updated_at: 61.minutes.ago) }
    let!(:order_cycle5) { create(:simple_order_cycle, orders_close_at: 1.minute.from_now) }

    it "returns closed order cycles whose orders_close_at or updated_at date is within the last hour" do
      order_cycles = job.send(:recently_closed_order_cycles)
      expect(order_cycles).to include order_cycle3, order_cycle4
      expect(order_cycles).to_not include order_cycle1, order_cycle2, order_cycle5
    end
  end

  describe "processing an order" do
    let(:shop) { create(:distributor_enterprise) }
    let(:order_cycle1) { create(:simple_order_cycle, coordinator: shop) }
    let(:order_cycle2) { create(:simple_order_cycle, coordinator: shop) }
    let(:schedule1) { create(:schedule, order_cycles: [order_cycle1, order_cycle2]) }
    let(:subscription1) { create(:subscription, shop: shop, schedule: schedule1, with_items: true) }
    let(:proxy_order) { create(:proxy_order, subscription: subscription1) }
    let(:order) { proxy_order.initialise_order! }

    before do
      while !order.completed? do break unless order.next! end
      allow(job).to receive(:send_confirm_email).and_call_original
      job.instance_variable_set(:@order, order)
      Spree::MailMethod.create!(
        environment: Rails.env,
        preferred_mails_from: 'spree@example.com'
      )
      expect(job).to receive(:record_order).with(order)
    end

    context "when payments need to be processed" do
      let(:payment_method) { create(:payment_method) }
      let(:payment) { double(:payment, amount: 10) }

      before do
        allow(order).to receive(:payment_total) { 0 }
        allow(order).to receive(:total) { 10 }
        allow(order).to receive(:pending_payments) { [payment] }
      end

      context "and an error is added to the order when updating payments" do
        before { expect(job).to receive(:update_payment!) { order.errors.add(:base, "a payment error") } }

        it "sends a failed payment email" do
          expect(job).to receive(:send_failed_payment_email)
          expect(job).to_not receive(:send_confirm_email)
          job.send(:process!)
        end
      end

      context "and no errors are added when updating payments" do
        before { expect(job).to receive(:update_payment!) { true } }

        context "when an error occurs while processing the payment" do
          before do
            expect(payment).to receive(:process!).and_raise Spree::Core::GatewayError, "payment failure error"
          end

          it "sends a failed payment email" do
            expect(job).to receive(:send_failed_payment_email)
            expect(job).to_not receive(:send_confirm_email)
            job.send(:process!)
          end
        end

        context "when payments are processed without error" do
          before do
            expect(payment).to receive(:process!) { true }
            expect(payment).to receive(:completed?) { true }
          end

          it "sends only a subscription confirm email, no regular confirmation emails" do
            ActionMailer::Base.deliveries.clear
            expect{ job.send(:process!) }.to_not enqueue_job ConfirmOrderJob
            expect(job).to have_received(:send_confirm_email).once
            expect(ActionMailer::Base.deliveries.count).to be 1
          end
        end
      end
    end
  end

  describe "#send_confirm_email" do
    let(:order) { double(:order) }
    let(:mail_mock) { double(:mailer_mock, deliver: true) }

    before do
      job.instance_variable_set(:@order, order)
      allow(SubscriptionMailer).to receive(:confirmation_email) { mail_mock }
    end

    it "records a success and sends the email" do
      expect(job).to receive(:record_success).with(order).once
      job.send(:send_confirm_email)
      expect(SubscriptionMailer).to have_received(:confirmation_email).with(order)
      expect(mail_mock).to have_received(:deliver)
    end
  end

  describe "#send_failed_payment_email" do
    let(:order) { double(:order) }
    let(:mail_mock) { double(:mailer_mock, deliver: true) }

    before do
      job.instance_variable_set(:@order, order)
      allow(SubscriptionMailer).to receive(:failed_payment_email) { mail_mock }
    end

    it "records and logs an error and sends the email" do
      expect(job).to receive(:record_and_log_error).with(:failed_payment, order).once
      job.send(:send_failed_payment_email)
      expect(SubscriptionMailer).to have_received(:failed_payment_email).with(order)
      expect(mail_mock).to have_received(:deliver)
    end
  end
end
