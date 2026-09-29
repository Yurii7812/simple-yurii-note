// 関係グラフ (d3-force)。ノートをノード、リンクをエッジで表示。
import { forceSimulation, forceLink, forceManyBody, forceCenter, forceCollide } from "d3-force";

const SVG_NS = "http://www.w3.org/2000/svg";

export function createGraph(container, { onOpen } = {}) {
  let sim = null;
  let svg = null;
  let g = null;
  let linkSel = null;
  let nodeSel = null;
  let width = 800;
  let height = 600;

  function ensure() {
    if (svg) return;
    svg = document.createElementNS(SVG_NS, "svg");
    svg.setAttribute("class", "graph-svg");
    g = document.createElementNS(SVG_NS, "g");
    svg.appendChild(g);
    container.appendChild(svg);
  }

  function resize() {
    const r = container.getBoundingClientRect();
    width = Math.max(300, r.width);
    height = Math.max(300, r.height);
    if (svg) svg.setAttribute("viewBox", `${-width / 2} ${-height / 2} ${width} ${height}`);
    if (sim) { sim.force("center", forceCenter(0, 0)); sim.alpha(0.3).restart(); }
  }

  function setData(nodes, links) {
    ensure();
    resize();
    if (sim) sim.stop();

    const nodeMap = new Map(nodes.map((n) => [n.id, { ...n }]));
    const ls = links
      .filter((l) => nodeMap.has(l.source) && nodeMap.has(l.target))
      .map((l) => ({ source: l.source, target: l.target }));
    const ns = [...nodeMap.values()];

    linkSel?.remove();
    nodeSel?.remove();
    while (g.firstChild) g.removeChild(g.firstChild);

    linkSel = document.createElementNS(SVG_NS, "g");
    nodeSel = document.createElementNS(SVG_NS, "g");
    g.append(linkSel, nodeSel);

    const linkEls = ls.map((l) => {
      const el = document.createElementNS(SVG_NS, "line");
      el.setAttribute("class", "graph-link");
      linkSel.appendChild(el);
      return el;
    });
    const nodeEls = ns.map((n) => {
      const el = document.createElementNS(SVG_NS, "g");
      el.setAttribute("class", "graph-node" + (n.attr === "group" ? " graph-node-group" : ""));
      const c = document.createElementNS(SVG_NS, "circle");
      c.setAttribute("r", n.attr === "group" ? 7 : 4.5);
      const t = document.createElementNS(SVG_NS, "text");
      t.setAttribute("dx", 8);
      t.setAttribute("dy", 4);
      t.textContent = (n.title || n.id).slice(0, 24);
      el.append(c, t);
      el.addEventListener("click", () => onOpen?.(n.id));
      nodeSel.appendChild(el);
      return el;
    });

    sim = forceSimulation(ns)
      .force("link", forceLink(ls).id((d) => d.id).distance(50).strength(0.4))
      .force("charge", forceManyBody().strength(-80))
      .force("center", forceCenter(0, 0))
      .force("collide", forceCollide(12))
      .on("tick", () => {
        linkEls.forEach((el, i) => {
          el.setAttribute("x1", ls[i].source.x);
          el.setAttribute("y1", ls[i].source.y);
          el.setAttribute("x2", ls[i].target.x);
          el.setAttribute("y2", ls[i].target.y);
        });
        nodeEls.forEach((el, i) => {
          el.setAttribute("transform", `translate(${ns[i].x},${ns[i].y})`);
        });
      });

    // 中央寄せ: text が右に出るので少し左へ
    g.setAttribute("transform", "translate(-120,0)");
  }

  const ro = new ResizeObserver(() => resize());
  ro.observe(container);

  return {
    setData,
    resize,
    destroy() { sim?.stop(); ro.disconnect(); svg?.remove(); svg = null; },
  };
}
