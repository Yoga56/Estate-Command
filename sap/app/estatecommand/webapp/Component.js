sap.ui.define([
  "sap/ui/core/UIComponent",
  "zestate/command/service/PlanService"
], function (UIComponent, PlanService) {
  "use strict";

  return UIComponent.extend("zestate.command.Component", {
    metadata: { manifest: "json" },

    init: function () {
      UIComponent.prototype.init.apply(this, arguments);
      this._service = new PlanService(this.getModel());
    },

    getService: function () {
      return this._service;
    }
  });
});
