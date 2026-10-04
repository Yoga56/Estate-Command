sap.ui.define([
  "sap/ui/core/Control",
  "sap/ui/core/ResizeHandler"
], function (Control, ResizeHandler) {
  "use strict";

  const PALETTES = {
    crew: null, // the crew's colour first, then the estate's neutrals
    estate: ["#1f5135", "#e8b33a", "#f4f1e8", "#7a3d1c", "#3d8b5a"],
    signal: ["#ff2a1a", "#ffffff", "#1a3cff", "#ffe11a"],
    mono: ["#121212", "#f2f2f2"]
  };

  /** Starting points, after the presets of Space Type Generator's _v.stripes */
  const PRESETS = {
    ribbon: { rows: 5, twist: 1.2, twistWaves: 1, wave: 4, speed: 1, fontScale: 0.72 },
    marquee: { rows: 4, twist: 0, twistWaves: 0, wave: 0, speed: 1.4, fontScale: 0.78 },
    wave: { rows: 6, twist: 0.45, twistWaves: 2, wave: 10, speed: 0.8, fontScale: 0.7 },
    flip: { rows: 3, twist: 3.14, twistWaves: 0.6, wave: 0, speed: 0.7, fontScale: 0.75 },
    stacks: { rows: 9, twist: 0.25, twistWaves: 1.4, wave: 2, speed: 0.5, fontScale: 0.8 }
  };

  const DEFAULTS = Object.assign({
    preset: "ribbon",
    gap: 3,
    palette: "crew",
    facts: ["block", "crew", "work", "mandays", "urgency", "deferral", "area", "road"],
    uppercase: true,
    animate: true
  }, PRESETS.ribbon);

  const SLICE = 3; // css px per column of the ribbon

  /** "#rrggbb" to perceived brightness 0..1 */
  const brightness = (hex) => {
    const n = parseInt(String(hex).replace("#", ""), 16);
    return (0.299 * (n >> 16 & 255) + 0.587 * (n >> 8 & 255) + 0.114 * (n & 255)) / 255;
  };

  /**
   * A block's facts as kinetic type: each fact runs along its own stripe, and the stripes turn
   * like ribbons and ripple, in the manner of Space Type Generator's _v.stripes
   * (spacetypegenerator.com/stripes). Canvas 2D, no library.
   *
   * facts:  [{ key, text }] - which of them show is config.facts
   * color:  the crew's colour, used by the "crew" palette
   * config: { preset, rows, gap, twist, twistWaves, wave, speed, fontScale, palette, facts, uppercase, animate };
   *         read on every frame, so a changed value shows at once; call refresh() when not animating
   */
  const BlockStripes = Control.extend("zestate.command.control.BlockStripes", {
    metadata: {
      properties: {
        facts: { type: "object", defaultValue: [] },
        color: { type: "string", defaultValue: "#3d8b5a" },
        config: { type: "object", defaultValue: null },
        height: { type: "sap.ui.core.CSSSize", defaultValue: "9rem" }
      }
    },

    renderer: {
      apiVersion: 2,
      render: function (rm, control) {
        rm.openStart("div", control).class("estStripes").style("height", control.getHeight()).openEnd();
        rm.voidStart("canvas").attr("aria-hidden", "true").voidEnd();
        rm.close("div");
      }
    },

    setFacts: function (facts) {
      this.setProperty("facts", facts, true);
      this.refresh();
      return this;
    },

    setColor: function (color) {
      this.setProperty("color", color, true);
      this.refresh();
      return this;
    },

    setConfig: function (config) {
      this.setProperty("config", config, true);
      this.refresh();
      return this;
    },

    /** The settings in force: the given config over the defaults */
    settings: function () {
      return Object.assign({}, DEFAULTS, this.getConfig() || {});
    },

    /** Rebuilds the stripes and draws a frame (the loop keeps drawing if animated) */
    refresh: function () {
      this._strips = null;
      if (this._canvas && this.settings().animate && !this._raf) {
        this._loop();
      } else {
        this._frame(performance.now());
      }
    },

    onBeforeRendering: function () {
      this._stop();
    },

    onAfterRendering: function () {
      this._canvas = this.getDomRef().querySelector("canvas");
      this._strips = null;
      this._resizeId = ResizeHandler.register(this, () => this.refresh());
      this._start = this._start || performance.now();
      this._loop();
    },

    exit: function () {
      this._stop();
    },

    _stop: function () {
      if (this._raf) {
        cancelAnimationFrame(this._raf);
        this._raf = null;
      }
      if (this._resizeId) {
        ResizeHandler.deregister(this._resizeId);
        this._resizeId = null;
      }
    },

    _loop: function () {
      const still = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      const tick = (now) => {
        this._frame(now);
        this._raf = this.settings().animate && !still && this.getDomRef() ? requestAnimationFrame(tick) : null;
      };
      tick(performance.now());
    },

    _colors: function (s) {
      return PALETTES[s.palette] || [this.getColor(), "#f4f1e8", "#10261c", "#e8b33a"];
    },

    _texts: function (s) {
      const shown = (this.getFacts() || []).filter((fact) => !s.facts || s.facts.indexOf(fact.key) >= 0);
      const texts = (shown.length ? shown : this.getFacts() || []).map((fact) => fact.text);
      return texts.length ? texts : ["ESTATE COMMAND"];
    },

    /** One stripe's text, repeated twice on its colour, face up and face down (the back of the ribbon) */
    _buildStrips: function (s, width, rowHeight, dpr) {
      const colors = this._colors(s);
      const texts = this._texts(s);
      const family = getComputedStyle(this.getDomRef()).fontFamily || "sans-serif";
      const font = "900 " + Math.max(6, Math.round(rowHeight * s.fontScale)) + "px " + family;
      const strips = [];
      for (let row = 0; row < s.rows; row++) {
        const color = colors[row % colors.length];
        const ink = brightness(color) > 0.6 ? "#10261c" : "#ffffff";
        let text = texts[row % texts.length];
        text = (s.uppercase ? text.toUpperCase() : text) + "   •   ";
        const measure = document.createElement("canvas").getContext("2d");
        measure.font = font;
        const unit = Math.max(Math.ceil(measure.measureText(text).width), 24);
        const copies = Math.ceil(width / unit) + 2;
        const face = (flip) => {
          const strip = document.createElement("canvas");
          strip.width = Math.ceil(unit * copies * dpr);
          strip.height = Math.max(1, Math.ceil(rowHeight * dpr));
          const ctx = strip.getContext("2d");
          ctx.scale(dpr, dpr);
          if (flip) {
            ctx.translate(0, rowHeight);
            ctx.scale(1, -1);
          }
          ctx.fillStyle = color;
          ctx.fillRect(0, 0, unit * copies, rowHeight);
          ctx.font = font;
          ctx.textBaseline = "middle";
          ctx.fillStyle = ink;
          for (let i = 0; i < copies; i++) {
            ctx.fillText(text, i * unit, rowHeight / 2 + rowHeight * 0.04);
          }
          if (flip) {
            ctx.setTransform(1, 0, 0, 1, 0, 0);
            ctx.fillStyle = "rgba(0, 0, 0, 0.28)";
            ctx.fillRect(0, 0, strip.width, strip.height);
          }
          return strip;
        };
        strips.push({ unit: unit, front: face(false), back: face(true) });
      }
      return strips;
    },

    _frame: function (now) {
      const canvas = this._canvas;
      const dom = this.getDomRef();
      if (!canvas || !dom) {
        return;
      }
      const s = this.settings();
      const dpr = window.devicePixelRatio || 1;
      const width = dom.clientWidth;
      const height = dom.clientHeight;
      if (!width || !height) {
        return;
      }
      if (canvas.width !== Math.round(width * dpr) || canvas.height !== Math.round(height * dpr)) {
        canvas.width = Math.round(width * dpr);
        canvas.height = Math.round(height * dpr);
        this._strips = null;
      }
      const rows = Math.max(1, Math.round(s.rows));
      const rowHeight = Math.max(4, (height - s.gap * (rows + 1)) / rows);
      const key = JSON.stringify([s.rows, s.gap, s.palette, s.facts, s.uppercase, s.fontScale, this.getFacts(),
        this.getColor(), width, height]);
      if (!this._strips || this._stripsKey !== key) {
        this._strips = this._buildStrips(Object.assign({}, s, { rows: rows }), width, rowHeight, dpr);
        this._stripsKey = key;
      }

      const ctx = canvas.getContext("2d");
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.scale(dpr, dpr);
      const t = (now - (this._start || now)) / 1000;

      this._strips.forEach((strip, row) => {
        const center = s.gap + rowHeight / 2 + row * (rowHeight + s.gap);
        const direction = row % 2 ? -1 : 1;
        const scroll = ((t * s.speed * 48 * direction) % strip.unit + strip.unit) % strip.unit;
        for (let x = 0; x < width; x += SLICE) {
          const along = x / width;
          const angle = s.twist * Math.sin(along * s.twistWaves * Math.PI * 2 + t * s.speed * 1.6 + row * 0.7);
          const turn = Math.cos(angle);
          const tall = Math.abs(turn) * rowHeight;
          if (tall < 0.5) {
            continue;
          }
          const y = center + s.wave * Math.sin(along * Math.PI * 2 + t * s.speed * 1.3 + row * 0.9) - tall / 2;
          const source = turn >= 0 ? strip.front : strip.back;
          const sx = ((x + scroll) % strip.unit) * dpr;
          ctx.drawImage(source, sx, 0, SLICE * dpr, source.height, x, y, SLICE + 0.6, tall);
          if (s.twist > 0) {
            // light falls off as the ribbon turns away
            ctx.fillStyle = "rgba(0, 0, 0, " + ((1 - Math.abs(turn)) * 0.45).toFixed(3) + ")";
            ctx.fillRect(x, y, SLICE + 0.6, tall);
          }
        }
      });
    }
  });

  BlockStripes.PRESETS = PRESETS;
  BlockStripes.DEFAULTS = DEFAULTS;
  BlockStripes.PALETTES = Object.keys(PALETTES);
  return BlockStripes;
});
