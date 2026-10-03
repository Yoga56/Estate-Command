sap.ui.define([
  "sap/ui/core/Control",
  "sap/ui/core/ResizeHandler"
], function (Control, ResizeHandler) {
  "use strict";

  const SVG = "http://www.w3.org/2000/svg";
  const PALETTE = ["#1f77b4", "#2ca02c", "#9467bd", "#8c564b", "#e377c2", "#17becf", "#bcbd22", "#ff7f0e",
    "#393b79", "#637939", "#7b4173", "#3182bd"];

  /** "lon lat,lon lat,..." to [[lon, lat], ...] */
  const parseRing = (text) => (text || "").split(",")
    .map((pair) => pair.trim().split(/\s+/).map(Number))
    .filter((point) => point.length === 2 && !isNaN(point[0]) && !isNaN(point[1]));

  /**
   * The estate's blocks drawn as SVG polygons - no map library, so it runs under the
   * launchpad's content security policy. A block is coloured by the crew assigned to it,
   * outlined red when it is due and not reached, and grey when nothing is due.
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

    onBeforeRendering: function () {
      this._deregister();
    },

    onAfterRendering: function () {
      this._draw();
      this._resizeId = ResizeHandler.register(this, () => this._draw());
    },

    exit: function () {
      this._deregister();
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
      const dom = this.getDomRef();
      if (!dom || !dom.clientWidth) {
        return;
      }
      dom.innerHTML = "";
      const width = dom.clientWidth;
      const height = this.getHeight();
      const blocks = (this.getBlocks() || []).map((b) => {
        const ring = parseRing(b.Geometry);
        const lon = Number(b.CentroidLon);
        const lat = Number(b.CentroidLat);
        return Object.assign({}, b, {
          ring: ring.length >= 3 ? ring : null,
          centroid: ring.length ? [ring.reduce((s, p) => s + p[0], 0) / ring.length, ring.reduce((s, p) => s + p[1], 0) / ring.length]
            : [lon, lat]
        });
      }).filter((b) => b.ring || (b.centroid[0] && b.centroid[1]));
      if (!blocks.length) {
        dom.textContent = "No block geometry for this estate yet: import its BLOCKS file.";
        return;
      }

      // equirectangular projection, scaled to fit
      const points = blocks.flatMap((b) => b.ring || [b.centroid]);
      const minLon = Math.min(...points.map((p) => p[0]));
      const maxLon = Math.max(...points.map((p) => p[0]));
      const minLat = Math.min(...points.map((p) => p[1]));
      const maxLat = Math.max(...points.map((p) => p[1]));
      const kx = Math.cos(((minLat + maxLat) / 2) * Math.PI / 180);
      const spanX = Math.max((maxLon - minLon) * kx, 1e-6);
      const spanY = Math.max(maxLat - minLat, 1e-6);
      const pad = 16;
      const scale = Math.min((width - 2 * pad) / spanX, (height - 2 * pad) / spanY);
      const x = (lon) => pad + (lon - minLon) * kx * scale;
      const y = (lat) => height - pad - (lat - minLat) * scale;
      const marker = Math.max(4, Math.min(14, scale * 0.002));

      const byBlock = {};
      (this.getLines() || []).forEach((line) => {
        (byBlock[line.BlockKey] = byBlock[line.BlockKey] || []).push(line);
      });
      const colors = this.crewColors();

      const svg = document.createElementNS(SVG, "svg");
      svg.setAttribute("width", width);
      svg.setAttribute("height", height);
      blocks.forEach((block) => {
        const lines = byBlock[block.BlockKey] || [];
        const assigned = lines.find((l) => l.IsAssigned);
        const missed = lines.find((l) => !l.IsAssigned);
        let shape;
        if (block.ring) {
          shape = document.createElementNS(SVG, "polygon");
          shape.setAttribute("points", block.ring.map((p) => x(p[0]).toFixed(1) + "," + y(p[1]).toFixed(1)).join(" "));
        } else {
          shape = document.createElementNS(SVG, "rect");
          shape.setAttribute("x", (x(block.centroid[0]) - marker / 2).toFixed(1));
          shape.setAttribute("y", (y(block.centroid[1]) - marker / 2).toFixed(1));
          shape.setAttribute("width", marker);
          shape.setAttribute("height", marker);
        }
        shape.setAttribute("class", "estBlock" + (assigned ? " estAssigned" : missed ? " estMissed" : ""));
        shape.setAttribute("fill", assigned ? colors[assigned.CrewCode] : missed ? "#f5d5d5" : "#e8e8e8");
        const title = document.createElementNS(SVG, "title");
        title.textContent = block.BlockLabel + (assigned ? " - " + assigned.CrewCode + " #" + assigned.SequenceNo
          : missed ? " - due, not reached" : "");
        shape.appendChild(title);
        shape.addEventListener("click", () => this.fireSelect({ block: block, lines: lines }));
        svg.appendChild(shape);

        if (assigned && block.ring) {
          const label = document.createElementNS(SVG, "text");
          label.setAttribute("x", x(block.centroid[0]).toFixed(1));
          label.setAttribute("y", y(block.centroid[1]).toFixed(1));
          label.setAttribute("class", "estLabel");
          label.textContent = assigned.SequenceNo;
          svg.appendChild(label);
        }
      });
      dom.appendChild(svg);
    }
  });
});
