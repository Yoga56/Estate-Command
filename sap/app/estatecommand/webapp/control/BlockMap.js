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

  const PALETTE = ["#1f77b4", "#2ca02c", "#9467bd", "#ff7f0e", "#e377c2", "#17becf", "#bcbd22", "#8c564b",
    "#393b79", "#637939", "#7b4173", "#3182bd"];
  // Esri World Imagery: satellite tiles without a key; zoomed in, the palms are visible
  const IMAGERY = "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}";
  const PLACES = "https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}";
  // a block without a polygon is drawn as a rectangle this many degrees around its centroid
  const HALF_LON = 0.00135;
  const HALF_LAT = 0.0045;

  /** "lon lat,lon lat,..." to Leaflet [[lat, lon], ...] */
  const parseRing = (text) => (text || "").split(",")
    .map((pair) => pair.trim().split(/\s+/).map(Number))
    .filter((point) => point.length === 2 && !isNaN(point[0]) && !isNaN(point[1]))
    .map((point) => [point[1], point[0]]);

  /**
   * The estate's blocks on satellite imagery (Leaflet). A block is filled with the colour of
   * the crew assigned to it and numbered in the order the crew works it; a block that is due
   * but not reached is outlined red; a block with nothing due is outlined white and left clear,
   * so the palms show through.
   *
   * blocks: [{ BlockKey, BlockLabel, Geometry, CentroidLon, CentroidLat }]
   * lines:  the plan's lines [{ BlockKey, CrewCode, IsAssigned, SequenceNo, ... }]
   * Fires "select" with the block and its plan lines when a block is clicked.
   */
  return Control.extend("zestate.command.control.BlockMap", {
    metadata: {
      properties: {
        blocks: { type: "object", defaultValue: [] },
        lines: { type: "object", defaultValue: [] },
        height: { type: "int", defaultValue: 560 }
      },
      events: {
        select: { parameters: { block: { type: "object" }, lines: { type: "object" } } }
      }
    },

    renderer: {
      apiVersion: 2,
      render: function (rm, control) {
        rm.openStart("div", control).class("estMap").style("height", control.getHeight() + "px").openEnd().close("div");
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
        this._map = L.map(dom, { zoomControl: true, attributionControl: true, maxZoom: 19 });
        L.tileLayer(IMAGERY, {
          maxZoom: 19,
          maxNativeZoom: 18,
          attribution: "Imagery &copy; Esri, Maxar, Earthstar Geographics"
        }).addTo(this._map);
        L.tileLayer(PLACES, { maxZoom: 19, maxNativeZoom: 18, opacity: 0.8 }).addTo(this._map);
        this._layer = L.layerGroup().addTo(this._map);
        this._fitted = false;
      }
      this._draw();
      this._resizeId = ResizeHandler.register(this, () => this._map && this._map.invalidateSize());
    },

    exit: function () {
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
        const missed = lines.find((l) => !l.IsAssigned);
        const style = assigned
          ? { color: "#ffffff", weight: 1.5, fillColor: colors[assigned.CrewCode], fillOpacity: 0.55 }
          : missed
            ? { color: "#e00000", weight: 2.5, fillColor: "#e00000", fillOpacity: 0.15 }
            : { color: "#ffffff", weight: 1, fillOpacity: 0, dashArray: "4 3" };

        const polygon = L.polygon(ring, style)
          .bindTooltip(block.BlockLabel + (assigned ? " - " + assigned.CrewCode + " #" + assigned.SequenceNo
            : missed ? " - due, not reached" : " - not due"), { sticky: true })
          .on("click", () => this.fireSelect({ block: block, lines: lines }));
        this._layer.addLayer(polygon);
        bounds.extend(polygon.getBounds());

        if (assigned) {
          this._layer.addLayer(L.marker(polygon.getBounds().getCenter(), {
            interactive: false,
            icon: L.divIcon({ className: "estSeq", html: String(assigned.SequenceNo), iconSize: [22, 22] })
          }));
        }
      });

      if (!this._fitted && bounds.isValid()) {
        this._map.fitBounds(bounds, { padding: [16, 16] });
        this._fitted = true;
      } else if (!bounds.isValid()) {
        // nothing to show yet: the estates of the sample sit in Riau
        this._map.setView([1.60, 100.20], 12);
      }
    }
  });
});
