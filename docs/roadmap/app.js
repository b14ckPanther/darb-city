/* The Road to Darb: progress, the gold road, your pace, your notes. Everything stays in this browser. */
(() => {
  "use strict";

  const ROAD = window.DARB_ROAD;
  const KEY = "darb-road-book-v1";
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ---------- Days ---------- */
  const dayKey = (d = new Date()) => {
    const z = (n) => String(n).padStart(2, "0");
    return `${d.getFullYear()}-${z(d.getMonth() + 1)}-${z(d.getDate())}`;
  };
  const parse = (k) => {
    const [y, m, d] = k.split("-").map(Number);
    return new Date(y, m - 1, d);
  };
  const DAY = 86400000;
  const daysBetween = (a, b) => Math.round((parse(dayKey(b)) - parse(dayKey(a))) / DAY);

  /* ---------- State ---------- */
  const fresh = () => ({
    steps: {},
    you: {},
    stars: {},
    notes: {},
    // The first days of the road, before this book existed: the work happened every day.
    log: {
      "2026-10-12": 6,
      "2026-10-13": 5,
      "2026-10-14": 7,
      "2026-10-15": 8,
      "2026-10-16": 6,
      "2026-10-17": 7,
    },
    journal: {},
  });
  let state;
  try {
    state = { ...fresh(), ...JSON.parse(localStorage.getItem(KEY) || "{}") };
  } catch {
    state = fresh();
  }
  const save = () => {
    try {
      localStorage.setItem(KEY, JSON.stringify(state));
    } catch {
      /* private mode: progress lives until the tab closes */
    }
  };

  /* ---------- Model ---------- */
  const plans = [];
  ROAD.stages.forEach((stage, si) =>
    stage.plans.forEach((plan) => {
      plan.stage = stage;
      plan.si = si;
      plan.steps.forEach((s, i) => (s.id = `${plan.id}-${i}`));
      plans.push(plan);
    }),
  );
  const stepDone = (s) => (s.id in state.steps ? state.steps[s.id] : !!s.done);
  const planCount = (p) => p.steps.filter(stepDone).length;
  const planState = (p) => {
    const n = planCount(p);
    return n === p.steps.length ? "done" : n > 0 ? "moving" : "open";
  };
  const stageFrac = (st) => {
    const all = st.plans.flatMap((p) => p.steps);
    return all.filter(stepDone).length / all.length;
  };
  const allSteps = () => plans.flatMap((p) => p.steps);

  /* ---------- Build ---------- */
  const stagesEl = $("#stages");
  const planEls = new Map();

  ROAD.stages.forEach((stage, si) => {
    const el = $("#tpl-stage").content.firstElementChild.cloneNode(true);
    el.id = stage.id;
    el.dataset.stage = stage.id;
    if (stage.finale) el.classList.add("finale");
    $(".stage-n", el).textContent = stage.finale ? "The finish line" : `Stage ${String(si).padStart(2, "0")}`;
    $(".stage-name", el).textContent = stage.name;
    $(".ghost-n", el).textContent = stage.finale ? "★" : String(si).padStart(2, "0");
    $(".stage-line", el).textContent = stage.tagline;
    const box = $(".plans", el);
    stage.plans.forEach((plan) => {
      const p = $("#tpl-plan").content.firstElementChild.cloneNode(true);
      p.id = `plan-${plan.id}`;
      p.dataset.plan = plan.id;
      $(".ring b", p).textContent = plan.n;
      $(".p-title", p).textContent = plan.title;
      $(".p-line", p).textContent = plan.line;
      const meta = $(".p-meta", p);
      const pill = (cls, text) => {
        const s = document.createElement("span");
        s.className = `pill ${cls}`;
        s.textContent = text;
        meta.append(s);
      };
      pill("size", { S: "Hours", M: "Days", L: "Week+" }[plan.size] || plan.size);
      if (plan.ai) pill("smart", "Smart");
      if (plan.you || plan.steps.some((s) => s.you)) pill("you", "Needs you");
      const ul = $(".steps", p);
      plan.steps.forEach((s) => {
        const li = document.createElement("li");
        li.innerHTML = `<label class="step"><input type="checkbox" data-step="${s.id}"><span class="box"></span><span class="step-t"></span></label>`;
        $(".step-t", li).textContent = s.t;
        if (s.you) {
          const f = document.createElement("span");
          f.className = "pill you you-flag";
          f.textContent = "you";
          $(".step-t", li).append(f);
        }
        ul.append(li);
      });
      if (plan.you) {
        const hint = document.createElement("p");
        hint.className = "muted small";
        hint.textContent = `Needs from you: ${plan.you}`;
        hint.style.margin = "0 0 10px 12px";
        ul.after(hint);
      }
      const ta = $("textarea", p);
      ta.value = state.notes[plan.id] || "";
      ta.addEventListener("input", () => {
        state.notes[plan.id] = ta.value;
        save();
      });
      const star = $(".star", p);
      star.setAttribute("aria-pressed", String(!!state.stars[plan.id]));
      star.addEventListener("click", (e) => {
        e.preventDefault();
        e.stopPropagation();
        toggleStar(plan.id);
      });
      p.addEventListener("toggle", () => requestAnimationFrame(layoutRoad));
      box.append(p);
      planEls.set(plan.id, p);
    });
    stagesEl.append(el);
  });

  // The mini map of stages.
  ROAD.stages.forEach((stage, si) => {
    const li = document.createElement("li");
    li.innerHTML = `<a href="#${stage.id}"><span class="dot"></span><span></span><small></small></a>`;
    $("a span:nth-child(2)", li).textContent = stage.finale ? "The real Darb" : `${si}. ${stage.name}`;
    $("#mini").append(li);
  });

  // Waiting on you.
  ROAD.waiting.forEach((w) => {
    const li = document.createElement("li");
    li.innerHTML = `<label class="step"><input type="checkbox" data-you="${w.id}"><span class="box"></span><span class="step-t"></span></label>`;
    const t = $(".step-t", li);
    t.textContent = w.text;
    t.setAttribute("dir", "auto");
    if (w.link) {
      const a = document.createElement("a");
      a.href = w.link;
      a.target = "_blank";
      a.rel = "noopener";
      a.textContent = " open ↗";
      t.append(a);
    }
    $("input", li).checked = !!state.you[w.id];
    $("#you-list").append(li);
  });

  /* Numbers count to their new value when the motion layer is on. */
  const setNum = (sel, value) => {
    const el = $(sel);
    if (window.DarbMotion?.count) window.DarbMotion.count(el, value);
    else el.textContent = value;
  };

  /* ---------- Update ---------- */
  function update({ animateRoad = true } = {}) {
    let stepsDone = 0;
    let stepsAll = 0;
    let plansDone = 0;
    plans.forEach((plan) => {
      const el = planEls.get(plan.id);
      const n = planCount(plan);
      stepsDone += n;
      stepsAll += plan.steps.length;
      const st = planState(plan);
      if (st === "done") plansDone++;
      el.dataset.state = st;
      $(".r-arc", el).style.strokeDasharray = `${(n / plan.steps.length) * 100} 100`;
      $(".p-count", el).textContent =
        st === "done" ? "Finished" : `${n} of ${plan.steps.length} steps`;
      plan.steps.forEach((s) => ($(`[data-step="${s.id}"]`, el).checked = stepDone(s)));
    });
    ROAD.stages.forEach((stage, si) => {
      const f = stageFrac(stage);
      const el = $(`#${stage.id}`);
      el.dataset.state = f === 1 ? "done" : f > 0 ? "moving" : "open";
      $(".stage-bar span", el).style.width = `${f * 100}%`;
      const mini = $("#mini").children[si];
      $("a", mini).dataset.state = el.dataset.state;
      $("small", mini).textContent = `${Math.round(f * 100)}%`;
    });

    const pct = Math.round((stepsDone / stepsAll) * 100);
    setNum("#pct", pct);
    $("#dial-arc").style.strokeDasharray = `${(stepsDone / stepsAll) * 100} 100`;
    setNum("#st-steps", stepsDone);
    $("#st-plans").textContent = `${plansDone}/${plans.length}`;
    setNum("#st-streak", streak());
    setNum("#day-n", daysBetween(parse(ROAD.dayOne), new Date()) + 1);
    setNum("#st-left", Math.max(0, daysBetween(new Date(), parse(ROAD.launchTarget))));
    const open = ROAD.waiting.filter((w) => !state.you[w.id]).length;
    $("#you-count").textContent = open || "";

    renderNext();
    renderHeat();
    applyFilters();
    if (animateRoad) requestAnimationFrame(layoutRoad);
  }

  /* ---------- Next ---------- */
  function upcoming(n) {
    const out = [];
    const starred = plans.filter((p) => state.stars[p.id]);
    const order = [...starred, ...plans.filter((p) => !state.stars[p.id])];
    for (const p of order) {
      for (const s of p.steps) {
        if (!stepDone(s)) {
          out.push({ plan: p, step: s });
          break;
        }
      }
      if (out.length >= n) break;
    }
    return out;
  }
  function nextButton({ plan, step }) {
    const b = document.createElement("button");
    b.type = "button";
    b.className = "next-item";
    b.innerHTML = `<span><b></b><small></small></span>`;
    $("b", b).textContent = step.t;
    $("small", b).textContent = `${plan.stage.name} · ${plan.title}`;
    b.addEventListener("click", () => goToPlan(plan.id));
    return b;
  }
  function renderNext() {
    const list = $("#next-list");
    list.replaceChildren(
      ...upcoming(3).map((x) => {
        const li = document.createElement("li");
        li.append(nextButton(x));
        return li;
      }),
    );
    const t = $("#today-next");
    t.replaceChildren(
      ...upcoming(6).map((x) => {
        const li = document.createElement("li");
        li.append(nextButton(x));
        return li;
      }),
    );
  }
  function goToPlan(id) {
    showView("road");
    const el = planEls.get(id);
    resetFilters();
    el.open = true;
    el.scrollIntoView({ behavior: reduced ? "auto" : "smooth", block: "center" });
    el.animate?.(
      [{ boxShadow: "inset 0 0 0 2px #f0c77a" }, { boxShadow: "inset 0 0 0 1px rgba(217,165,76,.28)" }],
      { duration: 1600, easing: "ease-out" },
    );
  }

  /* ---------- Pace ---------- */
  function streak() {
    let n = 0;
    const d = new Date();
    if (!state.log[dayKey(d)]) d.setDate(d.getDate() - 1);
    while (state.log[dayKey(d)]) {
      n++;
      d.setDate(d.getDate() - 1);
    }
    return n;
  }
  function renderHeat() {
    const heat = $("#heat");
    const weeks = 18;
    heat.style.gridTemplateColumns = "";
    heat.style.gridTemplateRows = "repeat(7, 1fr)";
    heat.style.gridAutoFlow = "column";
    heat.style.gridAutoColumns = "1fr";
    const end = new Date();
    const start = new Date(end);
    start.setDate(end.getDate() - (weeks * 7 - 1) - end.getDay());
    const cells = [];
    const today = dayKey();
    for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
      const k = dayKey(d);
      const c = state.log[k] || 0;
      const i = document.createElement("i");
      i.dataset.l = c === 0 ? 0 : c < 2 ? 1 : c < 4 ? 2 : c < 7 ? 3 : 4;
      i.title = `${k}: ${c} step${c === 1 ? "" : "s"}`;
      if (k === today) i.dataset.today = "";
      cells.push(i);
    }
    heat.replaceChildren(...cells);
  }

  /* ---------- The road ---------- */
  const svg = $("#road-svg");
  const base = $("#road-base");
  const gold = $("#road-gold");
  const car = $("#road-car");
  function layoutRoad() {
    const wrap = $("#road");
    const box = wrap.getBoundingClientRect();
    const nodes = $$(".stage:not([hidden]) .node", wrap).map((n) => {
      const r = n.getBoundingClientRect();
      return [r.left - box.left + r.width / 2, r.top - box.top + r.height / 2, n.closest(".stage")];
    });
    if (nodes.length < 2) return;
    svg.setAttribute("viewBox", `0 0 ${box.width} ${box.height}`);
    // A road that sways a little between stations, never through the cards.
    const segs = [];
    let d = `M${nodes[0][0]} ${nodes[0][1]}`;
    for (let i = 1; i < nodes.length; i++) {
      const [x0, y0] = nodes[i - 1];
      const [x1, y1] = nodes[i];
      const sway = i % 2 ? -18 : 18;
      const c = ` C${x0 + sway} ${y0 + (y1 - y0) * 0.35} ${x1 + sway} ${y0 + (y1 - y0) * 0.65} ${x1} ${y1}`;
      segs.push(`M${x0} ${y0}${c}`);
      d += c;
    }
    base.setAttribute("d", d);
    gold.setAttribute("d", d);
    const total = gold.getTotalLength();
    const tmp = document.createElementNS("http://www.w3.org/2000/svg", "path");
    svg.append(tmp);
    const lens = [0];
    segs.forEach((s) => {
      tmp.setAttribute("d", s);
      lens.push(lens[lens.length - 1] + tmp.getTotalLength());
    });
    tmp.remove();
    // Gold up to the first stage still being travelled, and that far into it.
    const stages = nodes.map((n) => ROAD.stages.find((s) => s.id === n[2].dataset.stage));
    let at = lens[lens.length - 1];
    for (let i = 0; i < stages.length; i++) {
      const f = stageFrac(stages[i]);
      if (f < 1) {
        const next = lens[i + 1] ?? lens[i];
        at = lens[i] + (next - lens[i]) * f;
        break;
      }
    }
    gold.style.strokeDasharray = `${total}`;
    gold.style.strokeDashoffset = `${total - at}`;
    const p = gold.getPointAtLength(Math.max(0, Math.min(at, total)));
    car.setAttribute("cx", p.x);
    car.setAttribute("cy", p.y);
    dispatchEvent(new CustomEvent("road:layout"));
  }
  new ResizeObserver(() => layoutRoad()).observe(stagesEl);
  addEventListener("resize", layoutRoad);

  /* ---------- Ticking ---------- */
  const cheers = [
    "The road moved.",
    "One more stone on the road.",
    "Darb is closer.",
    "Every owner deserves this. Keep going.",
    "Gold. Next one.",
    "That's how a city gets built.",
  ];
  stagesEl.addEventListener("change", (e) => {
    const input = e.target.closest("[data-step]");
    if (!input) return;
    const plan = plans.find((p) => p.steps.some((s) => s.id === input.dataset.step));
    const stage = plan.stage;
    const wasPlan = planState(plan);
    const wasStage = stageFrac(stage);
    const step = plan.steps.find((s) => s.id === input.dataset.step);
    state.steps[step.id] = input.checked;
    if (input.checked) state.log[dayKey()] = (state.log[dayKey()] || 0) + 1;
    save();
    update();
    if (!input.checked) return;
    const r = input.closest(".step").getBoundingClientRect();
    if (stageFrac(stage) === 1 && wasStage < 1) {
      toast(`Stage complete`, `${stage.name}. The road is gold all the way here.`);
      burst(r.left + 20, r.top + 10, 140);
    } else if (planState(plan) === "done" && wasPlan !== "done") {
      window.DarbMotion?.sheen?.(planEls.get(plan.id));
      toast(`Plan ${plan.n} finished`, `${plan.title}. ${cheers[Math.floor(Math.random() * cheers.length)]}`);
      burst(r.left + 20, r.top + 10, 80);
    } else {
      const pct = $("#pct").textContent;
      toast(cheers[Math.floor(Math.random() * cheers.length)], `${pct}% of the road · ${streak()} day streak`);
      burst(r.left + 20, r.top + 10, 18);
    }
  });

  $("#you-list").addEventListener("change", (e) => {
    const input = e.target.closest("[data-you]");
    if (!input) return;
    state.you[input.dataset.you] = input.checked;
    if (input.checked) state.log[dayKey()] = (state.log[dayKey()] || 0) + 1;
    save();
    update({ animateRoad: false });
    if (input.checked) toast("Unblocked", "One less thing waiting on you.");
  });

  function toggleStar(id) {
    state.stars[id] = !state.stars[id];
    if (!state.stars[id]) delete state.stars[id];
    save();
    $(".star", planEls.get(id)).setAttribute("aria-pressed", String(!!state.stars[id]));
    renderNext();
    applyFilters();
  }

  /* ---------- Toast and burst ---------- */
  let toastTimer;
  function toast(title, body) {
    const t = $("#toast");
    t.innerHTML = "<b></b><span></span>";
    $("b", t).textContent = title;
    $("span", t).textContent = body;
    t.classList.add("show");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.classList.remove("show"), 2600);
  }

  const canvas = $("#burst");
  const ctx = canvas.getContext("2d");
  let parts = [];
  let raf = 0;
  function burst(x, y, n) {
    if (reduced) return;
    const dpr = Math.min(devicePixelRatio || 1, 2);
    canvas.width = innerWidth * dpr;
    canvas.height = innerHeight * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    for (let i = 0; i < n; i++) {
      const a = Math.random() * Math.PI * 2;
      const v = 2 + Math.random() * (n > 50 ? 7 : 4);
      parts.push({
        x,
        y,
        vx: Math.cos(a) * v,
        vy: Math.sin(a) * v - 2,
        life: 1,
        r: 1.5 + Math.random() * 2.5,
        hue: Math.random() < 0.7 ? "217,165,76" : "248,227,180",
      });
    }
    if (!raf) raf = requestAnimationFrame(tick);
  }
  function tick() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    parts = parts.filter((p) => p.life > 0);
    for (const p of parts) {
      p.x += p.vx;
      p.y += p.vy;
      p.vy += 0.12;
      p.vx *= 0.985;
      p.life -= 0.016;
      ctx.beginPath();
      ctx.fillStyle = `rgba(${p.hue},${Math.max(0, p.life)})`;
      ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
      ctx.fill();
    }
    raf = parts.length ? requestAnimationFrame(tick) : 0;
    if (!raf) ctx.clearRect(0, 0, canvas.width, canvas.height);
  }

  /* ---------- Filters ---------- */
  let filter = "all";
  const q = $("#q");
  function applyFilters() {
    const term = q.value.trim().toLowerCase();
    plans.forEach((plan) => {
      const el = planEls.get(plan.id);
      const st = planState(plan);
      const okFilter =
        filter === "all" ||
        (filter === "open" && st === "open") ||
        (filter === "moving" && st === "moving") ||
        (filter === "done" && st === "done") ||
        (filter === "smart" && plan.ai) ||
        (filter === "star" && state.stars[plan.id]);
      const text = `${plan.title} ${plan.line} ${plan.steps.map((s) => s.t).join(" ")} ${plan.stage.name}`.toLowerCase();
      const okTerm = !term || text.includes(term);
      el.hidden = !(okFilter && okTerm);
      if (term && okTerm && plan.steps.some((s) => s.t.toLowerCase().includes(term))) el.open = true;
    });
    ROAD.stages.forEach((stage) => {
      const el = $(`#${stage.id}`);
      el.hidden = stage.plans.every((p) => planEls.get(p.id).hidden);
    });
    requestAnimationFrame(layoutRoad);
  }
  function resetFilters() {
    q.value = "";
    filter = "all";
    $$(".chips button").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.filter === "all")));
    applyFilters();
  }
  q.addEventListener("input", applyFilters);
  $$(".chips button").forEach((b) =>
    b.addEventListener("click", () => {
      filter = b.dataset.filter;
      $$(".chips button").forEach((x) => x.setAttribute("aria-pressed", String(x === b)));
      applyFilters();
    }),
  );

  /* ---------- Views ---------- */
  function renderWhy() {
    const W = window.DARB_WHY;
    if (!W || $("#pillars").children.length) return;
    $("#why-line").textContent = W.line;
    W.pillars.forEach((p) => {
      const li = document.createElement("li");
      li.innerHTML = "<span></span><h3></h3><p></p>";
      $("span", li).textContent = p.n;
      $("h3", li).textContent = p.title;
      $("p", li).textContent = p.body;
      $("#pillars").append(li);
    });
    const head = document.createElement("div");
    head.className = "rv head";
    head.setAttribute("role", "row");
    head.innerHTML = '<span role="columnheader">App</span><span role="columnheader">Good at</span><span role="columnheader">Where it falls short</span>';
    $("#rivals").append(head);
    W.rivals.forEach((r) => {
      const row = document.createElement("div");
      row.className = "rv";
      row.setAttribute("role", "row");
      row.innerHTML = '<b role="cell"></b><span role="cell"></span><span role="cell"></span>';
      const [a, b, c] = row.children;
      a.textContent = r.name;
      b.textContent = r.good;
      c.textContent = r.gap;
      $("#rivals").append(row);
    });
    W.gaps.forEach((g) => {
      const li = document.createElement("li");
      li.innerHTML = "<b></b><span></span><small></small>";
      $("b", li).textContent = g.gap;
      $("span", li).textContent = g.fix;
      $("small", li).textContent = `Plans ${g.plans}`;
      $("#gaps").append(li);
    });
    $("#for-people").textContent = W.forPeople;
    $("#for-owners").textContent = W.forOwners;
    $("#focus").textContent = W.focus;
  }

  function showView(v) {
    $$(".tabs button").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.view === v)));
    const today = v === "today";
    const why = v === "why";
    $("main").hidden = today || why;
    $("#today-view").hidden = !today;
    $("#why-view").hidden = !why;
    if (why) {
      renderWhy();
      scrollTo({ top: 0 });
      window.DarbMotion?.whyIn?.();
    }
    if (today) {
      renderToday();
      scrollTo({ top: 0 });
    }
    if (v === "you") {
      const panel = $("#you-panel");
      panel.scrollIntoView({ behavior: reduced ? "auto" : "smooth", block: "center" });
      panel.classList.remove("flash");
      void panel.offsetWidth;
      panel.classList.add("flash");
    }
    if (!today && !why) requestAnimationFrame(layoutRoad);
  }
  $$(".tabs button").forEach((b) => b.addEventListener("click", () => showView(b.dataset.view)));

  function renderToday() {
    const k = dayKey();
    $("#today-date").textContent = new Date().toLocaleDateString("en-GB", {
      weekday: "long",
      day: "numeric",
      month: "long",
    });
    const n = state.log[k] || 0;
    const s = streak();
    $("#today-lede").textContent =
      n === 0
        ? `Nothing ticked yet today. Your streak is ${s} day${s === 1 ? "" : "s"}; one step keeps it alive.`
        : `${n} step${n === 1 ? "" : "s"} today. ${s} days in a row. The road is warm.`;
    const j = $("#journal");
    j.value = state.journal[k] || "";
    const past = Object.keys(state.journal)
      .filter((d) => d !== k && state.journal[d].trim())
      .sort()
      .reverse()
      .slice(0, 7);
    $("#journal-past").replaceChildren(
      ...past.map((d) => {
        const li = document.createElement("li");
        li.innerHTML = "<b></b><span></span>";
        $("b", li).textContent = parse(d).toLocaleDateString("en-GB", { day: "numeric", month: "short" });
        $("span", li).textContent = state.journal[d];
        return li;
      }),
    );
  }
  $("#journal").addEventListener("input", (e) => {
    state.journal[dayKey()] = e.target.value;
    save();
    $("#journal-saved").textContent = "Saved.";
  });

  /* ---------- Book tools ---------- */
  $("#export").addEventListener("click", () => {
    const blob = new Blob([JSON.stringify(state, null, 2)], { type: "application/json" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `darb-road-book-${dayKey()}.json`;
    a.click();
    URL.revokeObjectURL(a.href);
    toast("Backed up", "Your road book is saved as a file.");
  });
  $("#import").addEventListener("change", async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    try {
      const data = JSON.parse(await file.text());
      if (typeof data !== "object" || !data.steps) throw new Error();
      state = { ...fresh(), ...data };
      save();
      location.reload();
    } catch {
      toast("That file isn't a road book", "Choose a backup made with Back up.");
    }
  });
  $("#reset").addEventListener("click", () => {
    if (!confirm("Start over? Your ticks, notes and journal in this browser will be cleared.")) return;
    state = fresh();
    save();
    location.reload();
  });

  /* ---------- Keys ---------- */
  addEventListener("keydown", (e) => {
    const typing = /INPUT|TEXTAREA/.test(document.activeElement?.tagName || "");
    if (e.key === "Escape" && document.activeElement === q) {
      q.value = "";
      applyFilters();
      q.blur();
      return;
    }
    if (typing || e.metaKey || e.ctrlKey || e.altKey) return;
    if (e.key === "/") {
      e.preventDefault();
      showView("road");
      q.focus();
    } else if (e.key === "t") showView("today");
    else if (e.key === "r") showView("road");
    else if (e.key === "w") showView("why");
    else if (e.key === "s") {
      const open = $$(".plan[open]").pop();
      if (open) toggleStar(open.dataset.plan);
    }
  });

  window.DarbRoad = { layoutRoad, plans, planEls };

  /* ---------- Go ---------- */
  update();
  // The plan you are travelling now opens on arrival.
  const current = plans.find((p) => planState(p) === "moving");
  if (current) planEls.get(current.id).open = true;
  document.fonts?.ready.then(layoutRoad);
  addEventListener("load", layoutRoad);
})();
