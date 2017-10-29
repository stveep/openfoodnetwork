angular.module('admin.payments').factory 'Payment', (StripeElements, currentOrderNumber, paymentMethods, PaymentMethods, PaymentResource, Navigation, RailsFlashLoader)->
  new class Payment
    order: currentOrderNumber
    form_data: {}

    paymentMethodType: ->
      PaymentMethods.byID[@form_data.payment_method].method_type

    preprocess: ->
      munged_payment = {}
      munged_payment["payment"] = {payment_method_id: @form_data.payment_method, amount: @form_data.amount}
      munged_payment["order_id"] = @order
      # Not tested with Gateway other than Stripe. Could fall back to Rails for this?
      # Works ok without extra source_attrs for Cash, Bank Transfer etc.
      switch @paymentMethodType()
        when 'gateway'
          angular.extend munged_payment.payment, {
            source_attributes:
              number: @form_data.card_number
              month: @form_data.card_month
              year: @form_data.card_year
              verification_value: @form_data.card_verification_value
          }
        when 'stripe'
          angular.extend munged_payment.payment, {
            source_attributes:
              gateway_payment_profile_id: @form_data.token
              cc_type: @form_data.cc_type
              last_digits: @form_data.card.last4
              month: @form_data.card.exp_month
              year: @form_data.card.exp_year
          }
      munged_payment

    purchase: ->
      if @paymentMethodType() == 'stripe'
        StripeElements.requestToken(@form_data, @submit)
      else
        @submit()

    submit: =>
      munged = @preprocess()
      PaymentResource.create({order_id: munged.order_id}, munged, (response, headers, status)=>
        Navigation.go "/admin/orders/" + munged.order_id + "/payments"
      , (response) ->
        RailsFlashLoader.loadFlash({error: t("error saving payment")})
      )
