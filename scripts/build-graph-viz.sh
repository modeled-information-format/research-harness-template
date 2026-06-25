#!/usr/bin/env bash
# build-graph-viz.sh — render the MIF-native knowledge graph as a standalone
# HTML visualization (SPEC §4a: "keep the HTML graph visualization as an
# output"). Self-contained: it embeds the graph JSON and renders an interactive
# force-directed node-link diagram (deterministic layout, draggable nodes, typed
# edges) in vanilla SVG + JS — no external network dependency.
#
# Usage: build-graph-viz.sh <knowledge-graph.json> [<out.html>]
#
# The HTML view is an ephemeral, non-committed artifact. With no <out.html>, it
# defaults to a mktemp path OUTSIDE the project tree (never next to its input in
# reports/) so it can't dirty the working tree or block `copier update`. Callers
# that want an in-repo path (the sample fixture, the verify gate) pass $2.

set -uo pipefail
G="${1:?usage: build-graph-viz.sh <knowledge-graph.json> [out.html]}"
[ -f "$G" ] || { echo "build-graph-viz: not found: $G" >&2; exit 2; }

# No explicit out path -> a fresh mktemp dir OUTSIDE the tree (a dir, not a
# suffixed temp file, so no orphan empty temp is left behind). Guard the failure.
if [ -n "${2:-}" ]; then
  OUT="$2"
else
  TMPD=$(mktemp -d) || { echo "build-graph-viz: mktemp failed" >&2; exit 3; }
  OUT="$TMPD/knowledge-graph.html"
fi

# Embed the graph JSON verbatim inside a <script> tag below; escape any "</"
# so a label/id containing "</script>" can't terminate the tag early (injection
# when the file is opened locally). "\/" is a valid JSON string escape, so the
# embedded payload still parses identically.
DATA=$(sed 's#</#<\\/#g' "$G")
NODES=$(jq '.nodes|length' "$G")
EDGES=$(jq '.edges|length' "$G")

cat > "$OUT" <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Knowledge graph (MIF-native)</title>
<style>
  body { font-family: system-ui, sans-serif; margin: 1.5rem; color: #1a1a1a; }
  h1 { font-size: 1.1rem; margin: 0 0 .25rem; }
  .sub { color: #666; font-size: .85rem; margin: 0 0 .75rem; }
  #wrap { border: 1px solid #ddd; border-radius: 6px; background: #fcfcfc; }
  svg { width: 100%; height: auto; display: block; cursor: grab; }
  .legend { font-size: .8rem; color: #444; margin: .6rem 0 0; display: flex;
    flex-wrap: wrap; gap: 1rem; align-items: center; }
  .legend span { display: inline-flex; align-items: center; gap: .35rem; }
  .sw { width: 14px; height: 14px; border-radius: 50%; display: inline-block; }
  .ln { width: 22px; height: 0; display: inline-block; border-top-width: 3px;
    border-top-style: solid; }
  .node circle { cursor: grab; }
  .node text { font-size: 11px; fill: #222; pointer-events: none;
    paint-order: stroke; stroke: #fff; stroke-width: 3px; }
  .elabel { font-size: 9px; fill: #777; pointer-events: none; paint-order: stroke;
    stroke: #fcfcfc; stroke-width: 3px; }
</style>
</head>
<body>
<h1>Knowledge graph — $NODES nodes, $EDGES edges</h1>
<p class="sub">MIF-native: concepts &amp; entities (urn:mif: ids) linked by typed
  relationships and mentions. Drag nodes to rearrange.</p>
<div id="wrap"><svg id="svg" viewBox="0 0 1000 680" preserveAspectRatio="xMidYMid meet">
  <defs>
    <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7"
      markerHeight="7" orient="auto-start-reverse">
      <path d="M0,0 L10,5 L0,10 z" fill="#999"></path>
    </marker>
  </defs>
</svg></div>
<div class="legend" id="legend"></div>
<script id="graph" type="application/json">$DATA</script>
<script>
  const SVGNS = 'http://www.w3.org/2000/svg';
  const g = JSON.parse(document.getElementById('graph').textContent);
  const svg = document.getElementById('svg');
  const W = 1000, H = 680;

  const NODE_COLOR = { concept: '#16a34a', entity: '#2563eb' };
  const EDGE_STYLE = {
    supports:      { color: '#16a34a', dash: '' },
    contradicts:   { color: '#dc2626', dash: '6 4' },
    'derived-from':{ color: '#7c3aed', dash: '' },
    mentions:      { color: '#9ca3af', dash: '2 4' }
  };
  const estyle = function (t) { return EDGE_STYLE[t] || { color: '#999', dash: '' }; };

  const byId = new Map();
  g.nodes.forEach(function (n) { n.deg = 0; byId.set(n.id, n); });
  const links = g.edges
    .map(function (e) { return { s: byId.get(e.source), t: byId.get(e.target), type: e.type, strength: e.strength || 0.5 }; })
    .filter(function (l) { return l.s && l.t; });
  links.forEach(function (l) { l.s.deg++; l.t.deg++; });

  // Deterministic seed layout on a circle, then a fixed-iteration
  // Fruchterman-Reingold relaxation (no RNG -> stable output across runs).
  const N = g.nodes.length;
  g.nodes.forEach(function (n, i) {
    const a = (2 * Math.PI * i) / Math.max(N, 1);
    n.x = W / 2 + Math.cos(a) * Math.min(W, H) * 0.32;
    n.y = H / 2 + Math.sin(a) * Math.min(W, H) * 0.32;
  });
  const k = Math.sqrt((W * H) / Math.max(N, 1)) * 0.55;
  for (let it = 0; it < 400; it++) {
    g.nodes.forEach(function (n) { n.dx = 0; n.dy = 0; });
    for (let i = 0; i < N; i++) {
      for (let j = i + 1; j < N; j++) {
        const a = g.nodes[i], b = g.nodes[j];
        let ddx = a.x - b.x, ddy = a.y - b.y;
        let d = Math.sqrt(ddx * ddx + ddy * ddy) || 0.01;
        let f = (k * k) / d, ux = ddx / d, uy = ddy / d;
        a.dx += ux * f; a.dy += uy * f; b.dx -= ux * f; b.dy -= uy * f;
      }
    }
    links.forEach(function (l) {
      let ddx = l.s.x - l.t.x, ddy = l.s.y - l.t.y;
      let d = Math.sqrt(ddx * ddx + ddy * ddy) || 0.01;
      let f = (d * d) / k, ux = ddx / d, uy = ddy / d;
      l.s.dx -= ux * f; l.s.dy -= uy * f; l.t.dx += ux * f; l.t.dy += uy * f;
    });
    const temp = 12 * (1 - it / 400) + 0.4;
    g.nodes.forEach(function (n) {
      let dsp = Math.sqrt(n.dx * n.dx + n.dy * n.dy) || 0.01;
      let lim = Math.min(dsp, temp);
      n.x += (n.dx / dsp) * lim + (W / 2 - n.x) * 0.012;
      n.y += (n.dy / dsp) * lim + (H / 2 - n.y) * 0.012;
      n.x = Math.max(40, Math.min(W - 40, n.x));
      n.y = Math.max(30, Math.min(H - 30, n.y));
    });
  }

  const rad = function (n) { return 7 + Math.min(n.deg, 8) * 2.2; };
  const trunc = function (s) { return s.length > 32 ? s.slice(0, 31) + '…' : s; };

  // Edge layer
  const edgeEls = links.map(function (l) {
    const st = estyle(l.type);
    const line = document.createElementNS(SVGNS, 'line');
    line.setAttribute('stroke', st.color);
    line.setAttribute('stroke-width', String(1 + l.strength * 2.5));
    if (st.dash) line.setAttribute('stroke-dasharray', st.dash);
    line.setAttribute('marker-end', 'url(#arrow)');
    line.setAttribute('opacity', '0.8');
    svg.appendChild(line);
    const lab = document.createElementNS(SVGNS, 'text');
    lab.setAttribute('class', 'elabel');
    lab.setAttribute('text-anchor', 'middle');
    lab.textContent = l.type;
    svg.appendChild(lab);
    return { l: l, line: line, lab: lab };
  });

  // Node layer
  const nodeEls = g.nodes.map(function (n) {
    const grp = document.createElementNS(SVGNS, 'g');
    grp.setAttribute('class', 'node');
    const c = document.createElementNS(SVGNS, 'circle');
    c.setAttribute('r', String(rad(n)));
    c.setAttribute('fill', NODE_COLOR[n.kind] || '#888');
    c.setAttribute('stroke', '#fff');
    c.setAttribute('stroke-width', '1.5');
    const title = document.createElementNS(SVGNS, 'title');
    title.textContent = n.kind + ' · ' + n.label + '\n' + n.id;
    c.appendChild(title);
    grp.appendChild(c);
    const t = document.createElementNS(SVGNS, 'text');
    t.setAttribute('x', String(rad(n) + 4));
    t.setAttribute('y', '4');
    t.textContent = trunc(n.label);
    grp.appendChild(t);
    svg.appendChild(grp);
    return { n: n, grp: grp };
  });

  const place = function () {
    edgeEls.forEach(function (e) {
      e.line.setAttribute('x1', e.l.s.x); e.line.setAttribute('y1', e.l.s.y);
      e.line.setAttribute('x2', e.l.t.x); e.line.setAttribute('y2', e.l.t.y);
      e.lab.setAttribute('x', (e.l.s.x + e.l.t.x) / 2);
      e.lab.setAttribute('y', (e.l.s.y + e.l.t.y) / 2 - 2);
    });
    nodeEls.forEach(function (o) {
      o.grp.setAttribute('transform', 'translate(' + o.n.x + ',' + o.n.y + ')');
    });
  };
  place();

  // Drag interaction (SVG-space coords via the viewBox CTM).
  let drag = null;
  const toSvg = function (evt) {
    const r = svg.getBoundingClientRect();
    return { x: (evt.clientX - r.left) / r.width * W, y: (evt.clientY - r.top) / r.height * H };
  };
  nodeEls.forEach(function (o) {
    o.grp.addEventListener('mousedown', function (evt) { drag = o; evt.preventDefault(); });
  });
  window.addEventListener('mousemove', function (evt) {
    if (!drag) return;
    const p = toSvg(evt); drag.n.x = p.x; drag.n.y = p.y; place();
  });
  window.addEventListener('mouseup', function () { drag = null; });

  // Legend
  const leg = document.getElementById('legend');
  Object.keys(NODE_COLOR).forEach(function (kind) {
    const s = document.createElement('span');
    s.innerHTML = '<i class="sw" style="background:' + NODE_COLOR[kind] + '"></i>' + kind;
    leg.appendChild(s);
  });
  Object.keys(EDGE_STYLE).forEach(function (type) {
    const st = EDGE_STYLE[type];
    const s = document.createElement('span');
    s.innerHTML = '<i class="ln" style="border-top-color:' + st.color +
      (st.dash ? ';border-top-style:dashed' : '') + '"></i>' + type;
    leg.appendChild(s);
  });
</script>
</body>
</html>
HTML

echo "build-graph-viz: wrote $OUT"
