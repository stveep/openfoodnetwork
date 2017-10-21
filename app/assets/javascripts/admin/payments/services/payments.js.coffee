# Darkswarm.factory 'Payments', ()->
#   new class Payment
#     errors: {}
#     secrets: {}
#     order: CurrentOrder.order
#
#     purchase: ->
#       if @paymentMethod()?.method_type == 'stripe' && !@secrets.selected_card
#         StripeElements.requestToken(@secrets, @submit)
#       else
#         @submit()
