require 'open_food_network/proxy_order_syncer'

module OpenFoodNetwork
  describe ProxyOrderSyncer do
    describe "initialization" do
      let!(:subscription) { create(:subscription) }

      it "raises an error when initialized with an object that is not a Subscription or an ActiveRecord::Relation" do
        expect{ ProxyOrderSyncer.new(subscription) }.to_not raise_error
        expect{ ProxyOrderSyncer.new(Subscription.where(id: subscription.id)) }.to_not raise_error
        expect{ ProxyOrderSyncer.new("something") }.to raise_error RuntimeError
      end
    end

    describe "updating proxy_orders on a subscriptions" do
      let(:now) { Time.zone.now }
      let!(:schedule) { create(:schedule) }
      let!(:subscription) { create(:subscription, schedule: schedule, begins_at: now + 1.minute, ends_at: now + 2.minutes) }
      let!(:oc1) { create(:simple_order_cycle, schedules: [schedule], orders_open_at: now - 1.minute, orders_close_at: now) } # Closed
      let!(:oc2) { create(:simple_order_cycle, schedules: [schedule], orders_open_at: now - 1.minute, orders_close_at: now + 59.seconds) } # Open, but closes before begins at
      let!(:oc3) { create(:simple_order_cycle, schedules: [schedule], orders_open_at: now - 1.minute, orders_close_at: now + 1.minute) } # Open + closes on begins at
      let!(:oc4) { create(:simple_order_cycle, schedules: [schedule], orders_open_at: now - 1.minute, orders_close_at: now + 2.minutes) } # Open + closes on ends at
      let!(:oc5) { create(:simple_order_cycle, schedules: [schedule], orders_open_at: now - 1.minute, orders_close_at: now + 121.seconds) } # Open + closes after ends at
      let(:syncer) { ProxyOrderSyncer.new(subscription) }

      describe "#sync!" do
        let!(:oc6) { create(:simple_order_cycle, schedules: [schedule], orders_open_at: now - 1.minute, orders_close_at: now + 59.seconds) } # Open, but closes before begins at
        let!(:oc7) { create(:simple_order_cycle, schedules: [schedule], orders_open_at: now - 1.minute, orders_close_at: now + 61.seconds) } # Open + closes on begins at
        let!(:oc8) { create(:simple_order_cycle, schedules: [schedule], orders_open_at: now - 1.minute, orders_close_at: now + 121.seconds) } # Open + closes after ends at
        let!(:po1) { create(:proxy_order, subscription: subscription, order_cycle: oc6) }
        let!(:po2) { create(:proxy_order, subscription: subscription, order_cycle: oc7) }
        let!(:po3) { create(:proxy_order, subscription: subscription, order_cycle: oc8) }

        it "performs both create and remove actions to rectify proxy orders" do
          expect(syncer).to receive(:create_proxy_orders!).and_call_original
          expect(syncer).to receive(:remove_obsolete_proxy_orders!).and_call_original
          syncer.sync!
          subscription.reload
          expect(subscription.proxy_orders).to include po2
          expect(subscription.proxy_orders).to_not include po1, po3
          expect(subscription.proxy_orders.map(&:order_cycle)).to include oc3, oc4, oc7
          expect(subscription.proxy_orders.map(&:order_cycle)).to_not include oc1, oc2, oc5, oc6, oc8
        end
      end

      describe "#initialise_proxy_orders!" do
        let(:new_subscription) { build(:subscription, schedule: schedule, begins_at: now + 1.minute, ends_at: now + 2.minutes) }
        it "builds proxy orders for in-range order cycles that are not already closed" do
          allow(syncer).to receive(:subscription) { new_subscription }
          expect{ syncer.send(:initialise_proxy_orders!) }.to_not change(ProxyOrder, :count).from(0)
          expect{ new_subscription.save! }.to change(ProxyOrder, :count).from(0).to(2)
          expect(new_subscription.proxy_orders.map(&:order_cycle_id)).to include oc3.id, oc4.id
        end
      end

      describe "#create_proxy_orders!" do
        it "creates proxy orders for in-range order cycles that are not already closed" do
          allow(syncer).to receive(:subscription) { subscription }
          expect{ syncer.send(:create_proxy_orders!) }.to change(ProxyOrder, :count).from(0).to(2)
          expect(subscription.proxy_orders.map(&:order_cycle)).to include oc3, oc4
        end
      end

      describe "#remove_obsolete_proxy_orders!" do
        let!(:po1) { create(:proxy_order, subscription: subscription, order_cycle: oc1) }
        let!(:po2) { create(:proxy_order, subscription: subscription, order_cycle: oc2) }
        let!(:po3) { create(:proxy_order, subscription: subscription, order_cycle: oc3) }
        let!(:po4) { create(:proxy_order, subscription: subscription, order_cycle: oc4) }
        let!(:po5) { create(:proxy_order, subscription: subscription, order_cycle: oc5) }

        it "destroys proxy orders that are closed or out of range" do
          allow(syncer).to receive(:subscription) { subscription }
          expect{ syncer.send(:remove_obsolete_proxy_orders!) }.to change(ProxyOrder, :count).from(5).to(2)
          expect(subscription.proxy_orders.map(&:order_cycle)).to include oc3, oc4
        end
      end
    end
  end
end
