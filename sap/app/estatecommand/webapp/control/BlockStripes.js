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

  const stillMotion = () => window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Reduced motion in the operating system only sets the starting value of "animate";
  // the user's own switch decides from then on
  const DEFAULTS = Object.assign({
    preset: "ribbon",
    gap: 4,
    thickness: 56,
    angle: 0,
    palette: "crew",
    facts: ["block", "crew", "work", "mandays", "urgency", "deferral", "area", "road"],
    uppercase: true,
    animate: !stillMotion()
  }, PRESETS.ribbon);

  const SLICE = 5; // css px per column of the ribbon
  const OVERHANG = 40; // css px a stripe runs on past the box, so its ends never show
  const UNFURL_MS = 700; // one stripe running in or out
  const STAGGER_MS = 80; // between one stripe and the next
  const FLOW_MS = 1000 / 30; // the type flows at 30 frames a second: smooth enough, half the work of 60
  const REVEAL_MS = 1000 / 60; // running in and out is short, so it gets 60
  const ASIDE_MS = 500; // out of sight (background tab, behind the phone's sheet): look again this often

  /** "#rrggbb" to perceived brightness 0..1 */
  const brightness = (hex) => {
    const n = parseInt(String(hex).replace("#", ""), 16);
    return (0.299 * (n >> 16 & 255) + 0.587 * (n >> 8 & 255) + 0.114 * (n & 255)) / 255;
  };
  const easeOut = (k) => 1 - Math.pow(1 - k, 3);

  /**
   * A block's facts as kinetic type: each fact runs along its own stripe, and the stripes turn
   * like ribbons and ripple, in the manner of Space Type Generator's _v.stripes
   * (spacetypegenerator.com/stripes). Canvas 2D, no library, no box: the stripes fill the triangle
   * in the lower left corner of the control (style.css clips it), parallel to its long side.
   *
   * show() runs the stripes in from the bottom right, one after the other; hide() runs them out to
   * the top left and resolves when they are gone. The type flows the same way, up and to the left.
   *
   * facts:  [{ key, text }] - which of them show is config.facts
   * color:  the crew's colour, used by the "crew" palette
   * config: { preset, rows, thickness, gap, angle, twist, twistWaves, wave, speed, fontScale, palette, facts, uppercase,
   *           animate }; thickness is the most px a stripe gets (more stripes than fit share the room);
   *           animate off also drops the run in and out
   *         read on every frame, so a changed value shows at once; call refresh() when not animating
   */
  const BlockStripes = Control.extend("zestate.command.control.BlockStripes", {
    metadata: {
      properties: {
        facts: { type: "object", defaultValue: [] },
        color: { type: "string", defaultValue: "#3d8b5a" },
        config: { type: "object", defaultValue: null }
      }
    },

    renderer: {
      apiVersion: 2,
      render: function (rm, control) {
        rm.openStart("div", control).class("estStripes").attr("aria-hidden", "true").openEnd();
        rm.voidStart("canvas").voidEnd();
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

    /** Runs the stripes in, one after the other */
    show: function () {
      const done = this._reveal && this._reveal.done;
      this._shown = true;
      this._reveal = this.settings().animate ? { dir: 1, start: performance.now() } : null;
      if (done) {
        done();
      }
      this.refresh();
    },

    /** Runs the stripes out; resolves when they are gone */
    hide: function () {
      return new Promise((resolve) => {
        if (!this._shown || !this.settings().animate || !this._canvas) {
          this._shown = false;
          this._reveal = null;
          this.refresh();
          resolve();
          return;
        }
        this._reveal = { dir: -1, start: performance.now(), done: resolve };
        this.refresh();
      });
    },

    /** Rebuilds the stripes and draws a frame (the loop keeps drawing while animated) */
    refresh: function () {
      this._strips = null;
      if (this._canvas && this._wantsLoop() && !this._raf && !this._timer) {
        this._drawn = 0;
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
      this._drawn = 0;
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
      if (this._timer) {
        clearTimeout(this._timer);
        this._timer = null;
      }
      if (this._resizeId) {
        ResizeHandler.deregister(this._resizeId);
        this._resizeId = null;
      }
    },

    _wantsLoop: function () {
      return !!this._reveal || (this._shown && this.settings().animate);
    },

    /** Draws at most FLOW_MS apart (REVEAL_MS while running in or out); waits without drawing while out of sight */
    _loop: function () {
      const tick = (now) => {
        this._raf = null;
        this._timer = null;
        if (!this.getDomRef()) {
          return;
        }
        if (now - this._drawn >= (this._reveal ? REVEAL_MS : FLOW_MS) - 1) {
          this._drawn = now;
          this._frame(now);
        }
        if (!this._wantsLoop()) {
          return;
        }
        if (document.hidden || !this._inSight(now)) {
          this._timer = setTimeout(() => tick(performance.now()), ASIDE_MS);
        } else {
          this._raf = requestAnimationFrame(tick);
        }
      };
      tick(performance.now());
    },

    /** Whether the stripes can be seen at all; read from the styles at most every ASIDE_MS */
    _inSight: function (now) {
      if (!this._sightAt || now - this._sightAt >= ASIDE_MS) {
        const dom = this.getDomRef();
        this._sightAt = now;
        this._sight = !!dom && dom.offsetWidth > 0 && getComputedStyle(dom).visibility !== "hidden";
      }
      return this._sight;
    },

    /** How far stripe `row` has run in, 0..1 */
    _progress: function (row, rows, now) {
      const reveal = this._reveal;
      if (!reveal) {
        return this._shown ? 1 : 0;
      }
      const order = reveal.dir > 0 ? row : rows - 1 - row;
      const k = Math.min(1, Math.max(0, (now - reveal.start - order * STAGGER_MS) / UNFURL_MS));
      return reveal.dir > 0 ? easeOut(k) : 1 - easeOut(k);
    },

    _settle: function (rows, now) {
      const reveal = this._reveal;
      if (reveal && now - reveal.start > UNFURL_MS + rows * STAGGER_MS) {
        this._reveal = null;
        if (reveal.dir < 0) {
          this._shown = false;
        }
        if (reveal.done) {
          reveal.done();
        }
      }
    },

    _colors: function (s) {
      return PALETTES[s.palette] || [this.getColor(), "#f4f1e8", "#10261c", "#e8b33a"];
    },

    _texts: function (s) {
      const shown = (this.getFacts() || []).filter((fact) => !s.facts || s.facts.indexOf(fact.key) >= 0);
      const texts = (shown.length ? shown : this.getFacts() || []).map((fact) => fact.text);
      return texts.length ? texts : ["ESTATE COMMAND"];
    },

    /** One stripe's text, repeated on its colour, face up and face down (the back of the ribbon) */
    _buildStrips: function (s, width, rowHeight, dpr) {
      const colors = this._colors(s);
      const texts = this._texts(s);
      const family = getComputedStyle(this.getDomRef()).fontFamily || "sans-serif";
      const font = "900 " + Math.max(6, Math.round(rowHeight * s.fontScale)) + "px " + family;
      const measure = document.createElement("canvas").getContext("2d");
      measure.font = font;
      const strips = [];
      for (let row = 0; row < s.rows; row++) {
        const color = colors[row % colors.length];
        const ink = brightness(color) > 0.6 ? "#10261c" : "#ffffff";
        let text = texts[row % texts.length];
        text = (s.uppercase ? text.toUpperCase() : text) + "   •   ";
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
      const ctx = canvas.getContext("2d");
      if (!width || !height) {
        return;
      }
      if (canvas.width !== Math.round(width * dpr) || canvas.height !== Math.round(height * dpr)) {
        canvas.width = Math.round(width * dpr);
        canvas.height = Math.round(height * dpr);
        this._strips = null;
      }
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      const rows = Math.max(1, Math.round(s.rows));
      if (!this._shown && !this._reveal) {
        return;
      }

      // The stripes fill the corner triangle below the box's diagonal (top left to bottom right):
      // they run parallel to the diagonal, the first along it, the last in the corner, and flow
      // up and to the left. config.angle turns them off the diagonal.
      const diagonal = Math.hypot(width, height);
      const depth = width * height / diagonal; // from the diagonal to the corner
      const length = diagonal + 2 * OVERHANG;
      // the stack of stripes stays inside the triangle: thickness is the most a stripe gets, and
      // more stripes than fit at that thickness share the room; it keeps clear of the diagonal by the ripple
      const margin = Math.abs(s.wave) + 6;
      const room = Math.max(rows * 6, depth - 2 * margin - (rows - 1) * s.gap);
      const rowHeight = Math.max(6, Math.min(Number(s.thickness) || 56, room / rows));
      const offset = margin + (room - rows * rowHeight) / 2;
      const theta = Number(s.angle || 0) * Math.PI / 180;
      const cos = Math.cos(theta);
      const sin = Math.sin(theta);
      const along = [width / diagonal, height / diagonal]; // down the diagonal, to the bottom right
      const across = [-height / diagonal, width / diagonal]; // from the diagonal into the corner
      const u = [along[0] * cos - along[1] * sin, along[0] * sin + along[1] * cos];
      const n = [across[0] * cos - across[1] * sin, across[0] * sin + across[1] * cos];
      const middle = [diagonal / 2 * along[0] + depth / 2 * across[0], diagonal / 2 * along[1] + depth / 2 * across[1]];

      // refresh() and a new canvas size drop the strips; otherwise they are drawn once and reused
      if (!this._strips) {
        this._strips = this._buildStrips(Object.assign({}, s, { rows: rows }), length, rowHeight, dpr);
      }

      // local x runs along the stripes, local y across them
      ctx.setTransform(dpr * u[0], dpr * u[1], dpr * n[0], dpr * n[1],
        dpr * (middle[0] - length / 2 * u[0] - depth / 2 * n[0]), dpr * (middle[1] - length / 2 * u[1] - depth / 2 * n[1]));
      const t = (now - (this._start || now)) / 1000;
      const clock = s.animate ? t : 0;
      const entering = !this._reveal || this._reveal.dir > 0;
      ctx.fillStyle = "#000000"; // the shade of a turning ribbon: one colour, its strength in globalAlpha

      this._strips.forEach((strip, row) => {
        const progress = this._progress(row, rows, now);
        if (progress <= 0) {
          return;
        }
        // running in, a stripe comes from the bottom right; running out, it leaves to the top left
        const from = entering ? length * (1 - progress) : 0;
        const to = entering ? length : length * progress;
        const edge = entering ? from : to;
        const center = offset + rowHeight / 2 + row * (rowHeight + s.gap);
        // the type flows up the stripe, each stripe at its own pace
        const pace = s.speed * 48 * (1 + 0.18 * (row % 3));
        const scroll = ((clock * pace) % strip.unit + strip.unit) % strip.unit;
        const alpha = Math.min(1, 0.2 + progress * 1.2);
        for (let x = Math.floor(from / SLICE) * SLICE; x < to; x += SLICE) {
          const share = x / length;
          const angle = s.twist * Math.sin(share * s.twistWaves * Math.PI * 2 + clock * s.speed * 1.6 + row * 0.7);
          const turn = Math.cos(angle);
          // the moving end of a stripe is still curled
          const curl = this._reveal ? Math.min(1, Math.abs(x - edge) / 60) : 1;
          const tall = Math.abs(turn) * rowHeight * (0.35 + 0.65 * curl);
          if (tall < 0.5) {
            continue;
          }
          const y = center + s.wave * Math.sin(share * Math.PI * 2 + clock * s.speed * 1.3 + row * 0.9) - tall / 2;
          const source = turn >= 0 ? strip.front : strip.back;
          const sx = ((x + scroll) % strip.unit) * dpr;
          ctx.globalAlpha = alpha;
          ctx.drawImage(source, sx, 0, SLICE * dpr, source.height, x, y, SLICE + 0.6, tall);
          // light falls off as the ribbon turns away
          const shade = (1 - Math.abs(turn)) * 0.45;
          if (s.twist > 0 && shade > 0.02) {
            ctx.globalAlpha = alpha * shade;
            ctx.fillRect(x, y, SLICE + 0.6, tall);
          }
        }
      });
      ctx.globalAlpha = 1;
      this._settle(rows, now);
    }
  });

  BlockStripes.PRESETS = PRESETS;
  BlockStripes.DEFAULTS = DEFAULTS;
  BlockStripes.PALETTES = Object.keys(PALETTES);
  return BlockStripes;
});
