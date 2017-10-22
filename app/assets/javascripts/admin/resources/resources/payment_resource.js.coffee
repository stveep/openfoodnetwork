angular.module("admin.resources").factory 'PaymentResource', ($resource) ->
  $resource('/admin/orders/:order_id/payments.json', {order_id: "@order"}, {
    'create':
      method: 'POST'
  })
