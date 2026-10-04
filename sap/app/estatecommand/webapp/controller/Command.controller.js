sap.ui.define([
  "sap/ui/core/mvc/Controller",
  "sap/ui/model/json/JSONModel",
  "sap/m/MessageBox",
  "sap/m/MessageToast",
  "sap/ui/core/BusyIndicator",
  "zestate/command/control/BlockStripes"
], function (Controller, JSONModel, MessageBox, MessageToast, BusyIndicator, BlockStripes) {
  "use strict";

  const EMPTY_REPLAN = { CrewOut: "", CrewCode: "", CrewPresent: 0, RainMm: "", BlockHeld: "", ContiguityPct: "", ClearChanges: false };
  const OPERATIONS = [
    { key: "harvest", text: "Harvest", icon: "sap-icon://nutrition-activity" },
    { key: "prune", text: "Prune", icon: "sap-icon://scissors" },
    { key: "weed", text: "Weed", icon: "sap-icon://eraser" },
    { key: "spray", text: "Spray", icon: "sap-icon://weather-proofing" }
  ];
  const STATUS = {
    P: { text: "Proposed", state: "Information" },
    F: { text: "Figures only", state: "Warning" },
    A: { text: "Accepted", state: "Success" },
    R: { text: "Rejected", state: "Error" },
    D: { text: "Deferred", state: "Warning" }
  };
  const FACTS = [
    { key: "block", text: "Block" }, { key: "crew", text: "Crew and order" }, { key: "work", text: "Work due" },
    { key: "mandays", text: "Man-days" }, { key: "urgency", text: "Urgency" }, { key: "deferral", text: "Cost of waiting" },
    { key: "travel", text: "Travel" }, { key: "area", text: "Area and palms" }, { key: "planted", text: "Planted" },
    { key: "road", text: "Road" }, { key: "division", text: "Division" }
  ];
  const STRIPES_KEY = "zestate.command.stripes";
  const PANEL_WIDTH = 440; // default, px; the user drags it wider or narrower
  const PANEL_KEY = "zestate.command.panelWidth";
  const NARROW = "(max-width: 900px)"; // the panel becomes a sheet over the lower half (style.css)
  const PHONE = "(max-width: 600px)";

  /** The message an OData failure carries, else the error text. */
  const messageOf = (error) => (error && error.error && error.error.message) || (error && error.message) || String(error);
  const num = (value, digits) => Number(value || 0).toLocaleString(undefined, { maximumFractionDigits: digits === undefined ? 1 : digits });
  const FIRE_HOLD = "held back for fire";
  const isFireHold = (line) => String(line.LineNote || "").indexOf(FIRE_HOLD) === 0;
  const statusOf = (code) => STATUS[code] || { text: code || "No plan", state: "None" };
  const compact = (value) => new Intl.NumberFormat(undefined, { notation: "compact", maximumFractionDigits: 2 })
    .format(Number(value) || 0);
  const readStore = (key) => {
    try {
      return window.localStorage.getItem(key);
    } catch (e) {
      return null;
    }
  };
  const writeStore = (key, value) => {
    try {
      window.localStorage.setItem(key, value);
    } catch (e) {
      // storage blocked: the value lasts for this session only
    }
  };

  return Controller.extend("zestate.command.controller.Command", {
    onInit: function () {
      this._view = new JSONModel({
        estates: [], estate: "", subtitle: "", operation: "harvest", ops: [], plans: [], planUuid: "", plan: null,
        blocks: [], crews: [], legendTitle: "", legendOpen: true, panelOpen: true, insetRight: 0, insetBottom: 0,
        whyFacts: [], lineRows: { reached: [], missed: [] }, lineCounts: { reached: 0, missed: 0 }, fires: [], fire: null,
        selected: null, decision: { note: "", dueDate: null, expected: "" }, replan: Object.assign({}, EMPTY_REPLAN),
        question: "", answer: null, handover: null, outcomes: [], stores: []
      });
      this.getView().setModel(this._view, "view");

      this._stripes = new JSONModel(Object.assign(this._savedStripes(), { catalogue: FACTS }));
      this._stripes.attachPropertyChange(this.onStripesChange, this);
      this.getView().setModel(this._stripes, "stripes");

      // dropdowns and popovers render outside the view: this class lets style.css reach them while the app is open
      document.documentElement.classList.add("estApp");
      this._panelWidth = this._clampWidth(Number(readStore(PANEL_KEY)) || PANEL_WIDTH);
      this.byId("page").addEventDelegate({ onAfterRendering: () => this._applyPanelWidth() });
      this._insets();
      this._onResize = () => {
        this._panelWidth = this._clampWidth(this._panelWidth);
        this._applyPanelWidth();
        this._insets();
      };
      window.addEventListener("resize", this._onResize);
      this._onGrip = (event) => this._grip(event);
      document.addEventListener("pointerdown", this._onGrip);
      document.addEventListener("keydown", this._onGrip);
      document.addEventListener("dblclick", this._onGrip);

      this._service = this.getOwnerComponent().getService();
      this._plansByOp = {};
      this._busy(async () => {
        // nothing more is read until an estate is chosen
        const estates = await this._service.estates();
        this._view.setProperty("/estates", [{ Estate: "", EstateName: "Choose an estate\u2026" }].concat(estates));
        this._clearEstate();
      });
    },

    onExit: function () {
      document.documentElement.classList.remove("estApp");
      window.removeEventListener("resize", this._onResize);
      ["pointerdown", "keydown", "dblclick"].forEach((type) => document.removeEventListener(type, this._onGrip));
    },

    onEstateChange: function () {
      if (!this._view.getProperty("/estate")) {
        this._clearEstate();
        return;
      }
      this._busy(() => this._loadEstate());
    },

    /** Live hotspots from NASA FIRMS, read only when asked for: the fire button or Show on map */
    onFiresToggle: function (event) {
      if (event.getParameter("on") && this._firesFor !== this._view.getProperty("/estate")) {
        this._loadFires(this._view.getProperty("/estate"));
      }
    },

    onOperationSelect: function (event) {
      const item = event.getParameter("listItem");
      const op = item && item.getBindingContext("view").getProperty("key");
      if (op && op !== this._view.getProperty("/operation")) {
        this._view.setProperty("/operation", op);
        this._busy(() => this._showOperation());
      }
    },

    onPlanChange: function (event) {
      const key = event.getParameter("selectedItem") && event.getParameter("selectedItem").getKey();
      if (key) {
        this._busy(() => this._show(this._service.load(key)));
      }
    },

    onGenerate: function () {
      const v = this._view.getData();
      if (!v.estate) {
        MessageToast.show("Choose an estate first");
        return;
      }
      this._freshPlanFire();
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

    /** A plan about to be made reads FIRMS itself: its fire picture replaces an earlier live read in the strip */
    _freshPlanFire: function () {
      const fire = this._view.getProperty("/fire");
      if (fire && fire.live) {
        this._view.setProperty("/fire/live", false);
      }
    },

    onReplan: function () {
      this._freshPlanFire();
      const changes = Object.assign({}, this._view.getProperty("/replan"));
      changes.CrewPresent = Number(changes.CrewPresent) || 0;
      this._busy(async () => {
        await this._show(this._service.replan(changes));
        this._view.setProperty("/replan", Object.assign({}, EMPTY_REPLAN));
        await this._loadPlans(true);
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

    onTogglePanel: function () {
      const open = !this._view.getProperty("/panelOpen");
      this._view.setProperty("/panelOpen", open);
      this._insets();
      this.byId("panel").toggleStyleClass("estCollapsed", !open);
      this.byId("page").toggleStyleClass("estPanelClosed", !open);
      // the estate moves into the room the panel leaves, once the panel has slid
      setTimeout(() => this.byId("map").fit(true), 380);
    },

    onShowFires: async function () {
      const estate = this._view.getProperty("/estate");
      if (this._firesFor !== estate) {
        await this._loadFires(estate);
      }
      this.byId("map").fitFires();
    },

    onToggleLegend: function () {
      this._view.setProperty("/legendOpen", !this._view.getProperty("/legendOpen"));
    },

    onBlockSelect: function (event) {
      this._selection = (this._selection || 0) + 1;
      this.byId("blockCard").removeStyleClass("estLeaving");
      this._select(event.getParameter("block"), event.getParameter("lines") || [], event.getParameter("color"));
      this.byId("stripes").show();
    },

    /** The stripes run out and the card fades, then the block lets go - unless another was picked meanwhile */
    onBlockClose: async function () {
      const selection = this._selection;
      this.byId("blockCard").addStyleClass("estLeaving");
      await this.byId("stripes").hide();
      if (selection === this._selection) {
        this.byId("blockCard").removeStyleClass("estLeaving");
        this._view.setProperty("/selected", null);
      }
    },

    // --- the block stripes: settings kept per viewer in the browser

    onStripesSettings: function (event) {
      this.byId("stripesSettings").openBy(event.getSource());
    },

    onStripesPreset: function () {
      const preset = BlockStripes.PRESETS[this._stripes.getProperty("/preset")];
      if (preset) {
        Object.keys(preset).forEach((key) => this._stripes.setProperty("/" + key, preset[key]));
      }
      this._stripesChanged();
    },

    onStripesChange: function (event) {
      const path = event.getParameter("path");
      if (["rows", "thickness", "twist", "twistWaves", "wave", "speed", "fontScale"].indexOf(path.replace("/", "")) >= 0) {
        this._stripes.setProperty("/preset", "custom");
      }
      this._stripesChanged();
    },

    onStripesReset: function () {
      this._stripes.setData(Object.assign({}, BlockStripes.DEFAULTS, { catalogue: FACTS }));
      this._stripesChanged();
    },

    /** The room the plan panel takes from the map: on the right, or below on a narrow window */
    _insets: function () {
      const open = this._view.getProperty("/panelOpen");
      const narrow = window.matchMedia && window.matchMedia(NARROW).matches;
      this._view.setProperty("/insetRight", open && !narrow ? this._panelWidth + 32 : 0);
      // the sheet covers the lower 48 % of a narrow window, 60 % of a phone (style.css)
      const phone = window.matchMedia && window.matchMedia(PHONE).matches;
      this._view.setProperty("/insetBottom", open && narrow ? Math.round(window.innerHeight * (phone ? 0.6 : 0.48)) : 0);
    },

    // --- the plan panel's width: drag its left edge, arrow keys on the edge, double-click to reset

    _clampWidth: function (px) {
      return Math.round(Math.max(340, Math.min(px, Math.min(960, window.innerWidth - 360))));
    },

    _applyPanelWidth: function () {
      const page = this.byId("page").getDomRef();
      if (page) {
        page.style.setProperty("--estPanelWidth", this._panelWidth + "px");
      }
    },

    _setPanelWidth: function (px, final) {
      this._panelWidth = this._clampWidth(px);
      this._applyPanelWidth();
      if (final) {
        writeStore(PANEL_KEY, String(this._panelWidth));
        this._insets();
      }
    },

    _grip: function (event) {
      const grip = event.target && event.target.closest && event.target.closest(".estPanelGrip");
      if (!grip) {
        return;
      }
      if (event.type === "dblclick") {
        this._setPanelWidth(PANEL_WIDTH, true);
      } else if (event.type === "keydown") {
        const step = { ArrowLeft: 24, ArrowRight: -24 }[event.key];
        if (step) {
          event.preventDefault();
          this._setPanelWidth(this._panelWidth + step, true);
        }
      } else {
        event.preventDefault();
        const startX = event.clientX;
        const startWidth = this._panelWidth;
        const page = this.byId("page");
        page.addStyleClass("estResizing");
        const move = (e) => this._setPanelWidth(startWidth + startX - e.clientX, false);
        const up = (e) => {
          document.removeEventListener("pointermove", move);
          document.removeEventListener("pointerup", up);
          page.removeStyleClass("estResizing");
          this._setPanelWidth(startWidth + startX - e.clientX, true);
        };
        document.addEventListener("pointermove", move);
        document.addEventListener("pointerup", up);
      }
    },

    _stripesChanged: function () {
      const settings = Object.assign({}, this._stripes.getData());
      delete settings.catalogue;
      try {
        window.localStorage.setItem(STRIPES_KEY, JSON.stringify(settings));
      } catch (e) {
        // storage blocked: the settings last for this session only
      }
      this.byId("stripes").setConfig(this._stripes.getData());
    },

    _savedStripes: function () {
      let saved = {};
      try {
        saved = JSON.parse(window.localStorage.getItem(STRIPES_KEY) || "{}") || {};
      } catch (e) {
        saved = {};
      }
      return Object.assign({}, BlockStripes.DEFAULTS, saved);
    },

    // --- loading

    _loadEstate: async function () {
      const estate = this._view.getProperty("/estate");
      const record = this._view.getProperty("/estates").find((e) => e.Estate === estate) || {};
      this._view.setProperty("/subtitle", record.EstateName || estate);
      this.onBlockClose();
      this._view.setProperty("/emptyText", "No plan yet for this operation: press Plan Tomorrow.");
      // a new estate: its live hotspots are read again only when asked for
      this._firesFor = null;
      this._view.setProperty("/fires", []);
      this.byId("map").showFires(false);
      this._view.setProperty("/blocks", await this._service.blocks(estate));
      this._view.setProperty("/stores", []);
      this._view.setProperty("/handover", null);
      await this._loadPlans();
    },

    /** Plans of every operation, so each tile shows its latest; keepPlan: leave the plan on screen */
    _loadPlans: async function (keepPlan) {
      const estate = this._view.getProperty("/estate");
      const lists = await Promise.all(OPERATIONS.map((op) => this._service.plans(estate, op.key)));
      OPERATIONS.forEach((op, i) => {
        this._plansByOp[op.key] = lists[i].map((plan) => Object.assign(plan, { StatusText: statusOf(plan.Status).text }));
      });
      this._refreshOps();
      if (!keepPlan) {
        await this._showOperation();
      }
    },

    _refreshOps: function () {
      const current = this._view.getProperty("/operation");
      this._view.setProperty("/ops", OPERATIONS.map((op) => {
        const latest = (this._plansByOp[op.key] || [])[0];
        const due = latest ? Number(latest.BlocksDue) || 0 : 0;
        const assigned = latest ? Number(latest.BlocksAssigned) || 0 : 0;
        const percent = due ? Math.round(assigned / due * 100) : 0;
        return Object.assign({}, op, {
          selected: op.key === current,
          coverage: latest ? assigned + "/" + due : "–",
          statusText: latest ? statusOf(latest.Status).text : "No plan",
          state: latest ? statusOf(latest.Status).state : "None",
          // share of the due blocks the plan reaches; built from numbers only
          bar: "<div class=\"estBar estBar--" + (percent >= 60 ? "good" : percent >= 30 ? "fair" : "poor") +
            "\"><i style=\"width:" + percent + "%\"></i></div>"
        });
      }));
      this._view.setProperty("/plans", this._plansByOp[current] || []);
    },

    _showOperation: async function () {
      this._refreshOps();
      const plans = this._view.getProperty("/plans");
      if (plans.length) {
        await this._show(this._service.load(plans[0].PlanUuid));
      } else {
        this._view.setProperty("/plan", null);
        this._view.setProperty("/planUuid", "");
        this._view.setProperty("/crews", []);
        this.onBlockClose();
        this._legend();
        this._planFire(null);
      }
    },

    _show: async function (planPromise) {
      const plan = await planPromise;
      plan.StatusText = statusOf(plan.Status).text;
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
      this._why(plan, colors);
      this._legend();
      this._planFire(plan);

      // the block on the card follows the plan on screen
      const selected = this._view.getProperty("/selected");
      if (selected) {
        const block = this._view.getProperty("/blocks").find((b) => b.BlockKey === selected.key);
        const lines = (plan._Lines || []).filter((l) => l.BlockKey === selected.key);
        const assigned = lines.find((l) => l.IsAssigned);
        this._select(block, lines, assigned ? colors[assigned.CrewCode] : lines.length ? "#ff4d4f" : "#ffffff");
      }
    },

    /** Before an estate is chosen: an empty map over Sumatra, nothing read */
    _clearEstate: function () {
      this.onBlockClose();
      this._plansByOp = {};
      this._firesFor = null;
      this._view.setProperty("/subtitle", "Choose an estate");
      this._view.setProperty("/emptyText", "Choose an estate to see its blocks, tomorrow's plans and the fires around it.");
      this._view.setProperty("/blocks", []);
      this._view.setProperty("/fires", []);
      this._view.setProperty("/plan", null);
      this._view.setProperty("/planUuid", "");
      this._view.setProperty("/crews", []);
      this._view.setProperty("/stores", []);
      this._view.setProperty("/handover", null);
      this._view.setProperty("/fire", null);
      this._refreshOps();
      this._view.setProperty("/legendTitle", "No estate chosen");
    },

    /** Fire hotspots from NASA FIRMS, live: the layer on the map and the strip in the panel */
    _loadFires: async function (estate) {
      if (!estate) {
        return;
      }
      this._firesFor = estate;
      this._view.setProperty("/fires", []);
      this._view.setProperty("/fire", { text: "Reading NASA FIRMS fire hotspots\u2026", type: "Information", count: 0, live: true });
      try {
        const rows = await this._service.fires(estate);
        if (estate !== this._view.getProperty("/estate")) {
          return; // another estate was picked meanwhile
        }
        const status = rows.find((r) => r.IsStatus) || {};
        const hotspots = rows.filter((r) => !r.IsStatus);
        this._view.setProperty("/fires", hotspots);
        this.byId("map").showFires(true);
        this._view.setProperty("/fire", {
          text: "Now: " + (status.StatusText || "no answer from the fire service"),
          type: ["Information", "Error", "Warning", "Success"][Number(status.Criticality) || 0] || "Information",
          count: hotspots.length,
          live: true
        });
      } catch (error) {
        this._firesFor = null;
        this._view.setProperty("/fire", { text: "Fire hotspots unknown: " + messageOf(error), type: "Information", count: 0, live: true });
      }
    },

    /** The fire strip from the plan: what FIRMS said when the plan was made, and the blocks it held back */
    _planFire: function (plan) {
      const live = this._view.getProperty("/fire");
      if (live && live.live) {
        return; // a live read is newer than the plan
      }
      if (!plan) {
        this._view.setProperty("/fire", this._view.getProperty("/estate")
          ? { text: "Fire hotspots: not read yet.", type: "Information", count: 1 } : null);
        return;
      }
      const text = plan.FireText || "Fire hotspots: not read with this plan.";
      const held = Number(plan.FireHeld) || 0;
      this._view.setProperty("/fire", {
        text: "At planning: " + text,
        type: held > 0 ? "Error" : /unknown|not read/.test(text) ? "Information"
          : /no fire hotspots/.test(text) ? "Success" : "Warning",
        count: 1
      });
    },

    /** The Why tab: the scheduler's figures and the plan's lines, formatted for reading */
    _why: function (plan, colors) {
      const lines = plan._Lines || [];
      const row = (l) => ({
        crew: l.CrewCode,
        seq: "#" + l.SequenceNo,
        color: colors[l.CrewCode] || "#888888",
        block: l.BlockLabel,
        urgency: num(l.Urgency, 2),
        manDays: num(l.ManDays, 2),
        waiting: compact(l.Deferral),
        waitingFull: num(l.Deferral, 0) + " IDR"
      });
      const reached = lines.filter((l) => l.IsAssigned).map(row);
      const held = lines.filter((l) => !l.IsAssigned && isFireHold(l)).map(row);
      const missed = lines.filter((l) => !l.IsAssigned && !isFireHold(l)).map(row);
      this._view.setProperty("/lineRows", { reached: reached, held: held, missed: missed });
      this._view.setProperty("/lineCounts", { reached: reached.length, held: held.length, missed: missed.length });
      this._view.setProperty("/whyFacts", [
        { label: "Blocks", value: plan.BlocksAssigned + " of " + plan.BlocksDue + " due" },
        { label: "Man-days", value: num(plan.ManDaysDue) + " needed", note: num(plan.CapacityMd) + " available" },
        { label: "Value recovered", value: compact(plan.ValueRecovered) + " IDR", note: "of " + compact(plan.DeferralDue) + " due" },
        { label: "Upper bound", value: compact(plan.UpperBound) + " IDR", note: "gap " + num(plan.GapPercent) + "%" },
        { label: "Contiguity", value: num(plan.ContiguityPercent) + "% bonus", note: "costs " + compact(plan.ContiguityCost) + " IDR" },
        { label: "Swaps", value: String(plan.Swaps || 0) + " improvements" },
        { label: "Rain", value: num(plan.RainMm) + " mm, " + num(plan.RainProbability, 0) + "%", note: plan.WeatherSource },
        { label: "Fire", value: Number(plan.FireHeld) ? plan.FireHeld + " block(s) held back" : "none held back",
          note: plan.FireText || "not read with this plan" },
        { label: "Changes", value: plan.Overrides || "none" }
      ]);
    },

    _legend: function () {
      const op = OPERATIONS.find((o) => o.key === this._view.getProperty("/operation"));
      const plan = this._view.getProperty("/plan");
      const missed = plan ? (plan._Lines || []).filter((l) => !l.IsAssigned && !isFireHold(l)).length : 0;
      const held = plan ? (plan._Lines || []).filter(isFireHold).length : 0;
      this._view.setProperty("/legendTitle", op.text + (plan
        ? " · " + this._view.getProperty("/crews").length + " crews · " + missed + " not reached" +
          (held ? " · " + held + " held for fire" : "")
        : " · no plan"));
    },

    /** The block card: its stripes and its plan lines */
    _select: function (block, lines, color) {
      if (!block) {
        this.onBlockClose();
        return;
      }
      const assigned = lines.find((l) => l.IsAssigned);
      const line = assigned || lines[0];
      const state = assigned ? assigned.CrewCode + " · #" + assigned.SequenceNo + " in its round"
        : line && isFireHold(line) ? "Held back for fire" : line ? "Due, not reached" : "Nothing due";
      const facts = [
        { key: "block", text: "Block " + block.BlockLabel },
        { key: "crew", text: assigned ? assigned.CrewCode + " #" + assigned.SequenceNo : line ? "Not reached" : "Nothing due" }
      ];
      if (line) {
        facts.push(
          { key: "work", text: line.Activity + " " + num(line.Quantity) + " " + line.QtyUnit },
          { key: "mandays", text: num(line.ManDays) + " man-days" },
          { key: "urgency", text: "Urgency " + num(line.Urgency, 2) },
          { key: "deferral", text: "Waiting costs " + num(line.Deferral, 0) + " IDR" },
          { key: "travel", text: num(line.TravelKm) + " km travel" });
      }
      facts.push(
        { key: "area", text: num(block.PlantedHa) + " ha · " + num(block.Palms, 0) + " palms" },
        { key: "planted", text: "Planted " + (block.PlantedYear || "-") },
        { key: "road", text: "Road " + (block.RoadCondition || "-") },
        { key: "division", text: "Division " + (block.Division || "-") });

      this._view.setProperty("/selected", {
        key: block.BlockKey,
        label: block.BlockLabel,
        color: color || "#3d8b5a",
        state: state,
        facts: facts,
        rows: lines.map((l) => ({
          title: (l.IsAssigned ? l.CrewCode + " #" + l.SequenceNo : "Not reached") + ": " + l.Activity + " " +
            num(l.Quantity) + " " + l.QtyUnit,
          detail: num(l.ManDays) + " man-days, urgency " + num(l.Urgency, 2) + ", waiting costs " + num(l.Deferral, 0) + " IDR" +
            (l.LineNote ? " (" + l.LineNote + ")" : ""),
          state: l.IsAssigned ? "Success" : "Error"
        }))
      });
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
