sap.ui.loader.config({
  // Leaflet is a UMD bundle: let it register as a module instead of setting a global
  shim: { "zestate/command/thirdparty/leaflet/leaflet": { amd: true, exports: "L" } }
});

sap.ui.define([
  "sap/ui/core/Control",
  "sap/ui/core/ResizeHandler",
  "zestate/command/thirdparty/leaflet/leaflet"
], function (Control, ResizeHandler, L) {
  "use strict";

  const PALETTE = ["#4cc9f0", "#80ed99", "#b388ff", "#ffb703", "#ff70a6", "#2ec4b6", "#e9ff70", "#ff9f1c",
    "#70a1ff", "#a3e635", "#f472b6", "#38bdf8"];
  // Esri basemaps: no key, one host (server.arcgisonline.com) for the content security allowlist
  const ESRI = "https://server.arcgisonline.com/ArcGIS/rest/services/";
  const BASEMAPS = {
    satellite: { title: "Satellite", tiles: ["World_Imagery", "Reference/World_Boundaries_and_Places"], native: 18 },
    terrain: { title: "Terrain", tiles: ["World_Topo_Map"], native: 18 },
    dark: { title: "Dark", tiles: ["Canvas/World_Dark_Gray_Base", "Canvas/World_Dark_Gray_Reference"], native: 16 }
  };
  const BASEMAP_ORDER = ["satellite", "terrain", "dark"];
  const svg = (paths) => "<svg viewBox=\"0 0 24 24\" aria-hidden=\"true\">" + paths + "</svg>";
  const ICONS = {
    plus: svg("<path d=\"M12 5v14M5 12h14\"/>"),
    minus: svg("<path d=\"M5 12h14\"/>"),
    fit: svg("<path d=\"M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5\"/>"),
    layers: svg("<path d=\"M12 3 2 8l10 5 10-5-10-5z\"/><path d=\"m2 16 10 5 10-5\"/><path d=\"m2 12 10 5 10-5\"/>"),
    check: svg("<path d=\"m5 12 5 5 9-10\"/>"),
    fire: svg("<path d=\"M12 3c1 3.5 5 5.5 5 10a5 5 0 0 1-10 0c0-2.2 1.2-3.6 2.3-4.6.3 1.6 1.2 2.6 2.2 3C11 9 11.2 6 12 3z\"/>")
  };
  // fire sources: the satellite codes FIRMS uses, by instrument; MODIS pixels are 1 km, VIIRS 375 m
  const FIRE_SOURCES = [
    { key: "viirs-n", label: "VIIRS Suomi NPP", match: (f) => /VIIRS/i.test(f.Instrument) && /^(N|NPP|SNPP)$/i.test(f.Satellite) },
    { key: "viirs-n20", label: "VIIRS NOAA-20", match: (f) => /VIIRS/i.test(f.Instrument) && /^(N20|1)$/i.test(f.Satellite) },
    { key: "viirs-n21", label: "VIIRS NOAA-21", match: (f) => /VIIRS/i.test(f.Instrument) && /^(N21|2)$/i.test(f.Satellite) },
    { key: "modis-terra", label: "MODIS Terra", match: (f) => /MODIS/i.test(f.Instrument) && /^(T|Terra)$/i.test(f.Satellite) },
    { key: "modis-aqua", label: "MODIS Aqua", match: (f) => /MODIS/i.test(f.Instrument) && /^(A|Aqua)$/i.test(f.Satellite) }
  ];
  const FIRE_DEFAULTS = { merge: true, sources: { "viirs-n": true, "viirs-n20": true, "viirs-n21": true,
    "modis-terra": false, "modis-aqua": false } };
  const FIRE_KEY = "zestate.command.fireLayer";
  // detections closer than this are one fire on the ground (a VIIRS pixel)
  const MERGE_KM = 0.375;
  const sourceOf = (fire) => FIRE_SOURCES.find((source) => source.match(fire)) || { key: "other", label: "other" };
  const loadFireOptions = () => {
    try {
      const saved = JSON.parse(window.localStorage.getItem(FIRE_KEY) || "null");
      return saved && saved.sources ? { merge: saved.merge !== false, sources: Object.assign({}, FIRE_DEFAULTS.sources, saved.sources) }
        : JSON.parse(JSON.stringify(FIRE_DEFAULTS));
    } catch (e) {
      return JSON.parse(JSON.stringify(FIRE_DEFAULTS));
    }
  };

  // a block without a polygon is drawn as a rectangle this many degrees around its centroid
  const HALF_LON = 0.00135;
  const HALF_LAT = 0.0045;
  // block labels show from this zoom on
  const NEAR_ZOOM = 15;

  /** "lon lat,lon lat,..." to Leaflet [[lat, lon], ...] */
  const parseRing = (text) => (text || "").split(",")
    .map((pair) => pair.trim().split(/\s+/).map(Number))
    .filter((point) => point.length === 2 && !isNaN(point[0]) && !isNaN(point[1]))
    .map((point) => [point[1], point[0]]);

  const escape = (text) => String(text == null ? "" : text)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

  /** Tile x/y at zoom z holding a point, for the basemap thumbnails */
  const tileOf = (lat, lon, z) => {
    const n = Math.pow(2, z);
    const rad = lat * Math.PI / 180;
    return {
      x: Math.floor((lon + 180) / 360 * n),
      y: Math.floor((1 - Math.log(Math.tan(rad) + 1 / Math.cos(rad)) / Math.PI) / 2 * n)
    };
  };

  /**
   * A column of map buttons in the glass style, with a menu that opens beside it:
   * buttons [{ icon (svg), title, press(button, control) }]
   */
  const ButtonBar = L.Control.extend({
    onAdd: function () {
      const wrapper = L.DomUtil.create("div", "estMapCtl");
      L.DomEvent.disableClickPropagation(wrapper);
      L.DomEvent.disableScrollPropagation(wrapper);
      const bar = L.DomUtil.create("div", "estMapBar", wrapper);
      this.menu = L.DomUtil.create("div", "estMapMenu", wrapper);
      this.menu.hidden = true;
      this.options.buttons.forEach((button) => {
        const element = L.DomUtil.create("button", "estMapBtn", bar);
        element.type = "button";
        element.title = button.title;
        element.setAttribute("aria-label", button.title);
        element.innerHTML = button.icon;
        L.DomEvent.on(element, "click", (event) => {
          L.DomEvent.stop(event);
          button.press(element, this);
        });
      });
      return wrapper;
    }
  });

  /**
   * The estate's blocks on imagery (Leaflet), filling its container. A block is filled with the
   * colour of the crew assigned to it and carries the order the crew works it; a block that is due
   * but not reached is outlined red and pulses; a block with nothing due is a faint dashed outline,
   * so the palms show through. Zoomed in, every block shows its label.
   *
   * blocks: [{ BlockKey, BlockLabel, Geometry, CentroidLon, CentroidLat }]
   * lines:  the plan's lines [{ BlockKey, CrewCode, IsAssigned, SequenceNo, ... }]
   * selectedBlock: BlockKey to ring
   * insetRight, insetBottom: px covered by a panel; fitting and the map buttons keep clear of them
   * fires:  NASA FIRMS hotspots [{ Latitude, Longitude, Frp, Confidence, AcqDate, AcqTime, ... }], drawn on top
 * Fires "select" with the block and its plan lines when a block is clicked.
   */
  return Control.extend("zestate.command.control.BlockMap", {
    metadata: {
      properties: {
        blocks: { type: "object", defaultValue: [] },
        lines: { type: "object", defaultValue: [] },
        fires: { type: "object", defaultValue: [] },
        selectedBlock: { type: "string", defaultValue: "" },
        insetRight: { type: "int", defaultValue: 0 },
        insetTop: { type: "int", defaultValue: 0 },
        insetBottom: { type: "int", defaultValue: 0 },
        height: { type: "sap.ui.core.CSSSize", defaultValue: "100%" }
      },
      events: {
        select: { parameters: { block: { type: "object" }, lines: { type: "object" } } },
        "firesToggle": { parameters: { on: { type: "boolean" } } }
      }
    },

    renderer: {
      apiVersion: 2,
      render: function (rm, control) {
        rm.openStart("div", control).class("estMap").style("height", control.getHeight())
          .style("--estInsetRight", control.getInsetRight() + "px")
          .style("--estInsetBottom", control.getInsetBottom() + "px").openEnd().close("div");
      }
    },

    // new data redraws the layers; re-rendering the control would throw the map away
    setBlocks: function (blocks) {
      this.setProperty("blocks", blocks, true);
      this._fitted = false;
      this._draw();
      return this;
    },

    setLines: function (lines) {
      this.setProperty("lines", lines, true);
      this._draw();
      return this;
    },

    setFires: function (fires) {
      this.setProperty("fires", fires, true);
      this._drawFires();
      return this;
    },

    setSelectedBlock: function (key) {
      this.setProperty("selectedBlock", key || "", true);
      this._highlight();
      return this;
    },

    setInsetRight: function (px) {
      this.setProperty("insetRight", px, true);
      if (this.getDomRef()) {
        this.getDomRef().style.setProperty("--estInsetRight", px + "px");
      }
      return this;
    },

    setInsetBottom: function (px) {
      this.setProperty("insetBottom", px, true);
      if (this.getDomRef()) {
        this.getDomRef().style.setProperty("--estInsetBottom", px + "px");
      }
      return this;
    },

    onBeforeRendering: function () {
      this._deregister();
    },

    onAfterRendering: function () {
      const dom = this.getDomRef();
      if (this._map && this._map.getContainer() !== dom) {
        this._map.remove();
        this._map = null;
      }
      if (!this._map) {
        this._createMap(dom);
      }
      this._draw();
      this._drawFires();
      this._resizeId = ResizeHandler.register(this, () => this._map && this._map.invalidateSize());
    },

    exit: function () {
      this._closeMenu();
      this._deregister();
      if (this._map) {
        this._map.remove();
        this._map = null;
      }
    },

    _deregister: function () {
      if (this._resizeId) {
        ResizeHandler.deregister(this._resizeId);
        this._resizeId = null;
      }
    },

    _createMap: function (dom) {
      this._map = L.map(dom, { zoomControl: false, attributionControl: true, maxZoom: 19, zoomSnap: 0.25,
        wheelPxPerZoomLevel: 90 });
      this._map.attributionControl.setPrefix(false);
      this._basemap = null;
      this._setBasemap("satellite");
      this._layer = L.layerGroup().addTo(this._map);
      this._fireLayer = L.layerGroup().addTo(this._map);
      // the live layer is off until asked for: reading it calls NASA FIRMS
      this._firesOn = false;
      this._fireOptions = loadFireOptions();
      this._fitted = false;

      L.control.scale({ position: "bottomright", imperial: false, maxWidth: 110 }).addTo(this._map);
      new ButtonBar({
        position: "bottomright",
        buttons: [
          { icon: ICONS.plus, title: "Zoom in", press: () => this._map.zoomIn() },
          { icon: ICONS.minus, title: "Zoom out", press: () => this._map.zoomOut() },
          { icon: ICONS.fit, title: "Fit the estate", press: () => this.fit(true) },
          { icon: ICONS.fire, title: "Live fire hotspots (NASA FIRMS): show, hide, choose the sources",
            press: (button, bar) => this._toggleFireMenu(bar, button) },
          { icon: ICONS.layers, title: "Choose the basemap", press: (button, bar) => this._toggleMenu(bar, button) }
        ]
      }).addTo(this._map);
      this._map.on("click movestart", () => this._closeMenu());

      const near = () => dom.classList.toggle("estNear", this._map.getZoom() >= NEAR_ZOOM);
      this._map.on("zoomend", near);
      near();
    },

    /** The basemap menu: one entry per basemap, with a tile of the estate as its picture */
    _toggleMenu: function (bar, button) {
      if (!bar.menu.hidden && this._menuButton === button) {
        this._closeMenu();
        return;
      }
      this._closeMenu();
      const center = this._map.getCenter();
      const z = Math.max(3, Math.min(15, Math.round(this._map.getZoom()) - 1));
      const tile = tileOf(center.lat, center.lng, z);
      bar.menu.innerHTML = "";
      bar.menu.setAttribute("role", "menu");
      bar.menu.setAttribute("aria-label", "Basemap");
      BASEMAP_ORDER.forEach((key) => {
        const basemap = BASEMAPS[key];
        const item = L.DomUtil.create("button", "estMapMenuItem", bar.menu);
        item.type = "button";
        item.setAttribute("role", "menuitemradio");
        item.setAttribute("aria-checked", String(key === this._basemapKey));
        item.innerHTML = "<img alt=\"\" src=\"" + ESRI + basemap.tiles[0] + "/MapServer/tile/" + Math.min(z, basemap.native) +
          "/" + tile.y + "/" + tile.x + "\"><span>" + basemap.title + "</span>" + ICONS.check;
        L.DomEvent.on(item, "click", (event) => {
          L.DomEvent.stop(event);
          this._setBasemap(key);
          this._closeMenu();
          button.focus();
        });
      });
      bar.menu.hidden = false;
      button.setAttribute("aria-expanded", "true");
      this._menuBar = bar;
      this._menuButton = button;
      this._onMenuKey = (event) => {
        if (event.key === "Escape") {
          this._closeMenu();
          button.focus();
        }
      };
      document.addEventListener("keydown", this._onMenuKey);
      const checked = bar.menu.querySelector("[aria-checked=true]");
      if (checked) {
        checked.focus();
      }
    },

    /** The fire menu: the live layer on or off, which satellites, and whether nearby detections merge */
    _toggleFireMenu: function (bar, button) {
      if (!bar.menu.hidden && this._menuButton === button) {
        this._closeMenu();
        return;
      }
      this._closeMenu();
      const counts = {};
      (this.getFires() || []).forEach((fire) => {
        const key = sourceOf(fire).key;
        counts[key] = (counts[key] || 0) + 1;
      });
      const options = this._fireOptions;
      const item = (label, checked, note, press) => {
        const element = L.DomUtil.create("button", "estMapMenuItem estMapMenuItem--check", bar.menu);
        element.type = "button";
        element.setAttribute("role", "menuitemcheckbox");
        element.setAttribute("aria-checked", String(checked));
        element.innerHTML = "<span>" + escape(label) + (note ? "<small>" + escape(note) + "</small>" : "") + "</span>" + ICONS.check;
        L.DomEvent.on(element, "click", (event) => {
          L.DomEvent.stop(event);
          press();
          element.setAttribute("aria-checked", String(!(element.getAttribute("aria-checked") === "true")));
        });
        return element;
      };
      bar.menu.innerHTML = "";
      bar.menu.setAttribute("role", "menu");
      bar.menu.setAttribute("aria-label", "Fire hotspots");
      item("Live hotspots", this._firesOn, this._firesOn ? "NASA FIRMS, read" : "reads NASA FIRMS", () => {
        this.showFires(!this._firesOn);
        this.fireFiresToggle({ on: this._firesOn });
      });
      L.DomUtil.create("div", "estMapMenuRule", bar.menu);
      FIRE_SOURCES.forEach((source) => item(source.label, !!options.sources[source.key],
        counts[source.key] ? counts[source.key] + " detections" : this.getFires().length ? "none" : "", () => {
          options.sources[source.key] = !options.sources[source.key];
          this._saveFireOptions();
        }));
      L.DomUtil.create("div", "estMapMenuRule", bar.menu);
      item("Merge nearby detections", options.merge, "within 375 m, one dot per fire", () => {
        options.merge = !options.merge;
        this._saveFireOptions();
      });
      bar.menu.hidden = false;
      button.setAttribute("aria-expanded", "true");
      this._menuBar = bar;
      this._menuButton = button;
      this._onMenuKey = (event) => {
        if (event.key === "Escape") {
          this._closeMenu();
          button.focus();
        }
      };
      document.addEventListener("keydown", this._onMenuKey);
      bar.menu.querySelector("button").focus();
    },

    _saveFireOptions: function () {
      try {
        window.localStorage.setItem(FIRE_KEY, JSON.stringify(this._fireOptions));
      } catch (e) {
        // storage blocked: the choice lasts for this session
      }
      this._drawFires();
    },

    _closeMenu: function () {
      if (this._menuBar) {
        this._menuBar.menu.hidden = true;
        this._menuButton.setAttribute("aria-expanded", "false");
        document.removeEventListener("keydown", this._onMenuKey);
        this._menuBar = null;
      }
    },

    _setBasemap: function (key) {
      if (this._basemap) {
        this._map.removeLayer(this._basemap);
      }
      const basemap = BASEMAPS[key];
      this._basemap = L.layerGroup(basemap.tiles.map((service, i) => L.tileLayer(ESRI + service + "/MapServer/tile/{z}/{y}/{x}", {
        maxZoom: 19,
        maxNativeZoom: basemap.native,
        opacity: i ? 0.85 : 1,
        className: i ? "estTilesLabels" : "estTiles",
        attribution: i ? "" : "Tiles &copy; Esri, Maxar, Earthstar Geographics"
      }))).addTo(this._map);
      this._basemapKey = key;
      this.getDomRef().dataset.basemap = key;
    },

    /** Fits the estate into the part of the map no panel covers */
    fit: function (animate) {
      if (!this._map || !this._bounds || !this._bounds.isValid()) {
        return;
      }
      const options = { paddingTopLeft: [32, this.getInsetTop() + 32], paddingBottomRight: [this.getInsetRight() + 32, this.getInsetBottom() + 40],
        maxZoom: 17 };
      if (animate) {
        this._map.flyToBounds(this._bounds, Object.assign({ duration: 0.8 }, options));
      } else {
        this._map.fitBounds(this._bounds, options);
      }
    },

    /** Shows or hides the live fire layer */
    showFires: function (on) {
      this._firesOn = !!on;
      this._drawFires();
      return this;
    },

    /** Fits the estate and the fire hotspots around it */
    fitFires: function () {
      const points = (this.getFires() || []).map((f) => [Number(f.Latitude), Number(f.Longitude)]);
      if (!this._map || !points.length) {
        return;
      }
      if (!this._firesOn) {
        this._firesOn = true;
        this._drawFires();
      }
      const bounds = L.latLngBounds(points);
      if (this._bounds && this._bounds.isValid()) {
        bounds.extend(this._bounds);
      }
      this._map.flyToBounds(bounds, { paddingTopLeft: [48, this.getInsetTop() + 48],
        paddingBottomRight: [this.getInsetRight() + 48, this.getInsetBottom() + 56], maxZoom: 15, duration: 0.8 });
    },

    /** One marker per hotspot: a glowing dot, larger with more fire radiative power */
    /** The live hotspots, quietly: small dots, older ones fainter; nearby detections of any satellite merged */
    _drawFires: function () {
      if (!this._map) {
        return;
      }
      this._fireLayer.clearLayers();
      const button = this.getDomRef() && this.getDomRef().querySelectorAll(".estMapBtn")[3];
      if (button) {
        button.setAttribute("aria-pressed", String(this._firesOn));
      }
      if (!this._firesOn) {
        return;
      }
      const options = this._fireOptions;
      const fires = (this.getFires() || []).filter((fire) => {
        const key = sourceOf(fire).key;
        return (Number(fire.Latitude) || Number(fire.Longitude)) && (key === "other" || options.sources[key]);
      });
      const newest = fires.reduce((max, fire) => String(fire.AcqDate) > max ? String(fire.AcqDate) : max, "");

      // strongest first, so a merged fire sits where it burns hardest
      const groups = [];
      fires.slice().sort((a, b) => (Number(b.Frp) || 0) - (Number(a.Frp) || 0)).forEach((fire) => {
        const lat = Number(fire.Latitude);
        const lon = Number(fire.Longitude);
        const near = options.merge && groups.find((g) => {
          const dy = (g.lat - lat) * 111.32;
          const dx = (g.lon - lon) * 111.32 * Math.cos(lat * Math.PI / 180);
          return dx * dx + dy * dy <= MERGE_KM * MERGE_KM;
        });
        if (near) {
          near.fires.push(fire);
        } else {
          groups.push({ lat: lat, lon: lon, fires: [fire] });
        }
      });

      groups.forEach((group) => {
        const lead = group.fires[0];
        const frp = Number(lead.Frp) || 0;
        const size = Math.round(8 + Math.min(8, Math.sqrt(frp) * 1.3));
        const latest = group.fires.reduce((max, f) => String(f.AcqDate) > max ? String(f.AcqDate) : max, "");
        const age = latest === newest ? "new" : "old";
        const where = group.fires.some((f) => f.IsInside) ? "inside block " + escape(lead.NearestBlock)
          : escape(lead.DistanceKm) + " km from block " + escape(lead.NearestBlock);
        const passes = group.fires.slice(0, 6).map((f) => {
          const time = String(f.AcqTime || "").padStart(4, "0");
          return escape(f.AcqDate) + " " + time.slice(0, 2) + ":" + time.slice(2) + " &middot; " + escape(sourceOf(f).label) +
            " &middot; " + escape(f.Frp) + " MW";
        }).join("<br>") + (group.fires.length > 6 ? "<br>+" + (group.fires.length - 6) + " more" : "");
        this._fireLayer.addLayer(L.marker([group.lat, group.lon], {
          keyboard: false,
          zIndexOffset: 1000,
          icon: L.divIcon({
            className: "estFire estFire--" + age + (group.fires.length > 1 ? " estFire--multi" : "") +
              " estFire--" + escape(lead.Confidence || "nominal"),
            html: "<i></i>",
            iconSize: [size, size]
          })
        }).bindTooltip("<div class=\"estTipTitle\"><i style=\"background:#ff7a1a\"></i>Fire hotspot" +
          (group.fires.length > 1 ? " &middot; " + group.fires.length + " detections" : "") + "</div>" +
          "<div class=\"estTipText\">" + where + "<br>" + passes + "<br>UTC; confidence " + escape(lead.Confidence) + "</div>",
          { direction: "top", offset: [0, -size / 2], className: "estTip", opacity: 1 }));
      });
    },

    /** Crew code to colour, stable for the plan on screen */
    crewColors: function () {
      const crews = [...new Set((this.getLines() || []).filter((l) => l.IsAssigned).map((l) => l.CrewCode))].sort();
      return Object.fromEntries(crews.map((crew, i) => [crew, PALETTE[i % PALETTE.length]]));
    },

    _draw: function () {
      if (!this._map) {
        return;
      }
      this._map.invalidateSize();
      this._layer.clearLayers();
      this._polygons = {};

      const byBlock = {};
      (this.getLines() || []).forEach((line) => {
        (byBlock[line.BlockKey] = byBlock[line.BlockKey] || []).push(line);
      });
      const colors = this.crewColors();
      const bounds = L.latLngBounds([]);

      (this.getBlocks() || []).forEach((block) => {
        let ring = parseRing(block.Geometry);
        if (ring.length < 3) {
          const lat = Number(block.CentroidLat);
          const lon = Number(block.CentroidLon);
          if (!lat && !lon) {
            return;
          }
          ring = [[lat - HALF_LAT, lon - HALF_LON], [lat - HALF_LAT, lon + HALF_LON],
            [lat + HALF_LAT, lon + HALF_LON], [lat + HALF_LAT, lon - HALF_LON]];
        }
        const lines = byBlock[block.BlockKey] || [];
        const assigned = lines.find((l) => l.IsAssigned);
        const held = !assigned && lines.some((l) => String(l.LineNote || "").indexOf("held back for fire") === 0);
        const missed = !assigned && !held && lines.length > 0;
        const color = assigned ? colors[assigned.CrewCode] : held ? "#ff8a1f" : missed ? "#ff4d4f" : "#ffffff";
        const kind = assigned ? "assigned" : held ? "held" : missed ? "missed" : "idle";
        const style = assigned
          ? { color: color, weight: 1.5, opacity: 0.95, fillColor: color, fillOpacity: 0.42 }
          : held
            ? { color: color, weight: 2.5, opacity: 1, fillColor: color, fillOpacity: 0.28, dashArray: "1 5", lineCap: "round" }
            : missed
              ? { color: color, weight: 2, opacity: 0.95, fillColor: color, fillOpacity: 0.12, dashArray: "6 4" }
              : { color: color, weight: 1, opacity: 0.55, fillColor: "#ffffff", fillOpacity: 0.02, dashArray: "2 5" };

        const polygon = L.polygon(ring, Object.assign({ className: "estBlock estBlock--" + kind }, style))
          .bindTooltip(this._tooltip(block, assigned, missed || held, color, held), {
            sticky: true, direction: "top", offset: [0, -10], className: "estTip", opacity: 1
          })
          .on("mouseover", () => polygon.setStyle({ weight: style.weight + 1.5, fillOpacity: style.fillOpacity + 0.18 }))
          .on("mouseout", () => polygon.setStyle(style))
          .on("click", () => this.fireSelect({ block: block, lines: lines, color: color }));
        this._layer.addLayer(polygon);
        this._polygons[block.BlockKey] = polygon;
        bounds.extend(polygon.getBounds());

        const center = polygon.getBounds().getCenter();
        const badge = assigned
          ? "<span class=\"estPinSeq\" style=\"background:" + color + "\">" + escape(assigned.SequenceNo) + "</span>"
          : "";
        this._layer.addLayer(L.marker(center, {
          interactive: false,
          keyboard: false,
          icon: L.divIcon({
            className: "estPin estPin--" + kind,
            html: badge + "<span class=\"estPinLabel\">" + escape(block.BlockLabel) + "</span>",
            iconSize: null
          })
        }));
      });

      this._bounds = bounds;
      if (!this._fitted && bounds.isValid()) {
        this.fit(false);
        this._fitted = true;
      } else if (!bounds.isValid()) {
        // no estate chosen yet: Sumatra, where the estates of the samples lie
        this._map.setView([0.2, 101.6], 6);
      }
      this._highlight();
    },

    _tooltip: function (block, assigned, missed, color, held) {
      const state = assigned ? escape(assigned.CrewCode) + " &middot; #" + escape(assigned.SequenceNo)
        : held ? "held back for fire" : missed ? "due, not reached" : "nothing due";
      return "<div class=\"estTipTitle\"><i style=\"background:" + color + "\"></i>Block " + escape(block.BlockLabel) +
        "</div><div class=\"estTipText\">" + state + "</div>";
    },

    _highlight: function () {
      if (!this._polygons) {
        return;
      }
      const selected = this.getSelectedBlock();
      Object.keys(this._polygons).forEach((key) => {
        const element = this._polygons[key].getElement();
        if (element) {
          element.classList.toggle("estBlock--selected", key === selected);
        }
      });
      if (selected && this._polygons[selected]) {
        this._polygons[selected].bringToFront();
      }
    }
  });
});
