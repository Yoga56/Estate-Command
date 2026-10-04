sap.ui.define([
  "sap/ui/core/mvc/Controller",
  "sap/ui/model/json/JSONModel",
  "sap/m/MessageBox",
  "sap/m/MessageToast",
  "sap/ui/core/BusyIndicator"
], function (Controller, JSONModel, MessageBox, MessageToast, BusyIndicator) {
  "use strict";

  const EMPTY_REPLAN = { CrewOut: "", CrewCode: "", CrewPresent: 0, RainMm: "", BlockHeld: "", ContiguityPct: "", ClearChanges: false };

  /** The message an OData failure carries, else the error text. */
  const messageOf = (error) => (error && error.error && error.error.message) || (error && error.message) || String(error);

  return Controller.extend("zestate.command.controller.Command", {
    onInit: function () {
      this._view = new JSONModel({
        estates: [], estate: "", operation: "harvest", plans: [], planUuid: "", plan: null, blocks: [], crews: [],
        legend: "Loading the estate...", decision: { note: "", dueDate: null, expected: "" }, replan: Object.assign({}, EMPTY_REPLAN),
        question: "", answer: null, handover: null, outcomes: [], stores: []
      });
      this.getView().setModel(this._view, "view");
      this._service = this.getOwnerComponent().getService();
      this._busy(async () => {
        const estates = await this._service.estates();
        this._view.setProperty("/estates", estates);
        if (estates.length) {
          this._view.setProperty("/estate", estates[0].Estate);
          await this._loadEstate();
        }
      });
    },

    onEstateChange: function () {
      this._busy(() => this._loadEstate());
    },

    onOperationChange: function () {
      this._busy(() => this._loadPlans());
    },

    onPlanChange: function (event) {
      const key = event.getParameter("selectedItem") && event.getParameter("selectedItem").getKey();
      if (key) {
        this._busy(() => this._show(this._service.load(key)));
      }
    },

    onGenerate: function () {
      const v = this._view.getData();
      this._busy(async () => {
        await this._show(this._service.generate(v.estate, v.operation));
        await this._loadPlans(true);
        const plan = this._view.getProperty("/plan");
        MessageToast.show(plan.Status === "F"
          ? "Plan made from the scheduler's figures only: no AI provider answered (" + plan.ErrorText + ")"
          : "Plan made: figures from the scheduler, words from " + plan.ModelId + ", " + plan.AuditChecked + " figures audited");
      });
    },

    onDecide: function (event) {
      const decision = event.getSource().data("decision");
      const d = this._view.getProperty("/decision");
      this._busy(async () => {
        await this._show(this._service.decide(decision, d.note, d.dueDate, d.expected));
        await this._loadPlans(true);
        MessageToast.show(decision + " recorded in the decision log");
      });
    },

    onReplan: function () {
      const changes = Object.assign({}, this._view.getProperty("/replan"));
      changes.CrewPresent = Number(changes.CrewPresent) || 0;
      this._busy(async () => {
        await this._show(this._service.replan(changes));
        this._view.setProperty("/replan", Object.assign({}, EMPTY_REPLAN));
      });
    },

    onDraft: function () {
      this._busy(() => this._show(this._service.draftArtifact()));
    },

    onAsk: function () {
      const question = this._view.getProperty("/question");
      if (!question) {
        return;
      }
      this._busy(async () => this._view.setProperty("/answer", await this._service.ask(question)));
    },

    onHandover: function () {
      this._busy(async () => this._view.setProperty("/handover",
        await this._service.handover(this._view.getProperty("/estate"))));
    },

    onOutcomes: function () {
      if (!this._view.getProperty("/plan")) {
        return;
      }
      this._busy(async () => this._view.setProperty("/outcomes", await this._service.outcomes()));
    },

    onStores: function () {
      this._busy(async () => this._view.setProperty("/stores",
        await this._service.stores(this._view.getProperty("/estate"))));
    },

    onBlockSelect: function (event) {
      const block = event.getParameter("block");
      const lines = event.getParameter("lines") || [];
      const text = lines.length
        ? lines.map((l) => (l.IsAssigned ? l.CrewCode + " #" + l.SequenceNo : "not reached") + ": " + l.Activity + " " +
            l.Quantity + " " + l.QtyUnit + ", " + l.ManDays + " man-days, urgency " + l.Urgency + ", deferral " + l.Deferral +
            " IDR" + (l.LineNote ? " (" + l.LineNote + ")" : "")).join("\n")
        : "Nothing due on this block in the plan.";
      MessageBox.information(text, { title: "Block " + block.BlockLabel });
    },

    _loadEstate: async function () {
      const estate = this._view.getProperty("/estate");
      this._view.setProperty("/blocks", await this._service.blocks(estate));
      this._view.setProperty("/stores", []);
      this._view.setProperty("/handover", null);
      await this._loadPlans();
    },

    /** keepPlan: leave the plan on screen and only refresh the list */
    _loadPlans: async function (keepPlan) {
      const v = this._view.getData();
      const plans = await this._service.plans(v.estate, v.operation);
      this._view.setProperty("/plans", plans);
      if (keepPlan) {
        return;
      }
      if (plans.length) {
        await this._show(this._service.load(plans[0].PlanUuid));
      } else {
        this._view.setProperty("/plan", null);
        this._view.setProperty("/planUuid", "");
        this._view.setProperty("/crews", []);
        this._view.setProperty("/legend", "No plan yet for this operation: press Plan Tomorrow.");
      }
    },

    _show: async function (planPromise) {
      const plan = await planPromise;
      this._view.setProperty("/plan", plan);
      this._view.setProperty("/planUuid", plan.PlanUuid);
      this._view.setProperty("/answer", null);
      this._view.setProperty("/outcomes", []);

      const colors = this.byId("map").crewColors();
      const crews = {};
      (plan._Lines || []).filter((l) => l.IsAssigned).forEach((l) => {
        const crew = crews[l.CrewCode] = crews[l.CrewCode] ||
          { crew: l.CrewCode, range: l.CrewRange, present: l.CrewPresent, blocks: 0, manDays: 0, color: colors[l.CrewCode] };
        crew.blocks += 1;
        crew.manDays = Math.round((crew.manDays + Number(l.ManDays)) * 100) / 100;
      });
      this._view.setProperty("/crews", Object.values(crews));
      const missed = (plan._Lines || []).filter((l) => !l.IsAssigned).length;
      this._view.setProperty("/legend", "Coloured by crew, numbered in the order the crew works them; " +
        missed + " due blocks not reached are outlined red; grey is not due.");
    },

    _busy: async function (work) {
      BusyIndicator.show(200);
      try {
        await work();
      } catch (error) {
        MessageBox.error(messageOf(error));
      } finally {
        BusyIndicator.hide();
      }
    }
  });
});
