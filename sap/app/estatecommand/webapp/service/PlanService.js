sap.ui.define([
  "sap/ui/base/Object",
  "sap/ui/model/Filter",
  "sap/ui/model/FilterOperator",
  "sap/ui/model/Sorter"
], function (BaseObject, Filter, FilterOperator, Sorter) {
  "use strict";

  const NS = "com.sap.gateway.srvd.zui_est_cmd_o4.v0001.";

  /**
   * Reads plans, blocks and stores and calls the actions of OData V4 service ZUI_EST_CMD_O4.
   * Every method returns a promise. A plan is the header object with its _Lines array.
   */
  return BaseObject.extend("zestate.command.service.PlanService", {
    constructor: function (model) {
      BaseObject.call(this);
      this._model = model;
      this._context = null; // the plan on screen
    },

    estates: async function () {
      return this._list("/Estate", [], [new Sorter("Estate")], 200);
    },

    /** The estate's blocks with their polygon ("lon lat,lon lat,...") and centroid. */
    blocks: async function (estate) {
      return this._list("/Block", [new Filter("Estate", FilterOperator.EQ, estate)], [new Sorter("BlockKey")], 2000,
        { $select: "BlockKey,BlockLabel,Division,PlantedHa,Palms,PlantedYear,RoadCondition,CentroidLon,CentroidLat,Geometry" });
    },

    /** Plans of one estate and operation, newest first, without their lines. */
    plans: async function (estate, operation) {
      return this._list("/Plan",
        [new Filter("Estate", FilterOperator.EQ, estate), new Filter("Operation", FilterOperator.EQ, operation)],
        [new Sorter("PlanDate", true), new Sorter("CreatedAt", true)], 30,
        { $select: "PlanUuid,PlanDate,Status,Headline,ModelId,BlocksDue,BlocksAssigned,CreatedAt" });
    },

    /** One plan with its lines; it becomes the plan the actions work on. */
    load: async function (planUuid) {
      const binding = this._model.bindContext("/Plan(PlanUuid=" + planUuid + ")", undefined,
        { $expand: { _Lines: { $orderby: "LineNumber" } } });
      this._context = binding.getBoundContext();
      return this._context.requestObject();
    },

    generate: async function (estate, operation, providerId) {
      const operationBinding = this._model.bindContext("/Plan/" + NS + "GeneratePlan(...)");
      operationBinding.setParameter("Estate", estate);
      operationBinding.setParameter("Operation", operation);
      operationBinding.setParameter("ProviderId", providerId || "");
      await this._invoke(operationBinding);
      const created = operationBinding.getBoundContext().getObject();
      return this.load(created.PlanUuid);
    },

    replan: async function (changes) {
      await this._action("Replan", Object.assign({
        CrewOut: "", CrewCode: "", CrewPresent: 0, RainMm: "", BlockHeld: "", ContiguityPct: "",
        ClearChanges: false, ProviderId: ""
      }, changes));
      return this._reload();
    },

    refreshWords: async function () {
      await this._action("RefreshWords", { ProviderId: "" });
      return this._reload();
    },

    /** decision: "Accept" | "Reject" | "Defer" */
    decide: async function (decision, note, dueDate, expectedEffect) {
      await this._action(decision, { DecisionNote: note || "", DueDate: dueDate || null, ExpectedEffect: expectedEffect || "" });
      return this._reload();
    },

    draftArtifact: async function () {
      await this._action("DraftArtifact");
      return this._reload();
    },

    /** { Answer, ModelId, AuditChecked, AuditUnverified } */
    ask: async function (question) {
      const operation = await this._action("Ask", { Question: question });
      return operation.getBoundContext().getObject();
    },

    outcomes: async function () {
      const operation = await this._action("Outcomes");
      return operation.getBoundContext().getObject().value;
    },

    handover: async function (estate) {
      const operation = this._model.bindContext("/Plan/" + NS + "Handover(...)");
      operation.setParameter("Estate", estate);
      await this._invoke(operation);
      return operation.getBoundContext().getObject();
    },

    /** NASA FIRMS hotspots around the estate: one row with IsStatus (what was read, or why not), then the hotspots, nearest first */
    fires: async function (estate) {
      return this._list("/Fire", [new Filter("Estate", FilterOperator.EQ, estate)], [], 500);
    },

    stores: async function (estate) {
      return this._list("/Stores", [new Filter("Estate", FilterOperator.EQ, estate)], [], 200);
    },

    _reload: async function () {
      const plan = this._context.getObject();
      return this.load(plan.PlanUuid);
    },

    _action: async function (name, parameters) {
      await this._context.requestObject(); // the ETag the action needs
      const operation = this._model.bindContext(NS + name + "(...)", this._context);
      Object.keys(parameters || {}).forEach((key) => operation.setParameter(key, parameters[key]));
      await this._invoke(operation);
      return operation;
    },

    _list: async function (path, filters, sorters, top, parameters) {
      const binding = this._model.bindList(path, undefined, sorters, filters, parameters);
      const contexts = await binding.requestContexts(0, top);
      return contexts.map((context) => context.getObject());
    },

    _invoke: function (operation) {
      // invoke() replaced execute() in UI5 1.123
      return operation.invoke ? operation.invoke() : operation.execute();
    }
  });
});
