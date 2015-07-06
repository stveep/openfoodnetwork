describe "EnterprisesCtrl", ->
  ctrl = null
  scope = null
  Enterprises = null

  beforeEach ->
    module('admin.enterprises')
    inject ($controller, $rootScope, _Enterprises_) ->
      scope = $rootScope
      Enterprises = _Enterprises_
      spyOn(Enterprises, "index").andReturn "list of enterprises"
      ctrl = $controller 'enterprisesCtrl', {$scope: scope, Enterprises: Enterprises}

  describe "setting the shop on scope", ->
    it "calls Enterprises#index with the correct params", ->
      expect(Enterprises.index).toHaveBeenCalled()

    it "resets $scope.allEnterprises with the result of Enterprises#index", ->
      expect(scope.allEnterprises).toEqual "list of enterprises"
