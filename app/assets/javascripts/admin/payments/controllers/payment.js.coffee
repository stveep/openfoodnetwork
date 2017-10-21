angular.module("admin.payments").controller "PaymentCtrl", ($scope, $timeout) ->
  $scope.form_data = {
    amount: '',
    payment_method: ''
  }
  # Need to get the amount, payment method from the form.
  # Order number is injected
  $scope.submitPayment = () ->
    # If stripe, get token then submitPayment
    console.log "not submitting"
    return false


    # Otherwise just submit

    # Default form action is sth like: /admin/orders/R257708112/payments
