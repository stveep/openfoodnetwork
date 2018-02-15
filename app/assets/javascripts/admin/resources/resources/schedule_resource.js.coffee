angular.module("admin.resources").factory 'ScheduleResource', ($resource) ->
  $resource('/admin/schedules/:id/:action.json', {}, {
    'index':
      method: 'GET'
      isArray: true
    'create':
      method: 'POST'
    'update':
      method: 'PUT'
      params:
        id: '@id'
    'destroy':
      method: 'DELETE'
      params:
        id: '@id'
  })
