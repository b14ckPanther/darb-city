/*
 * The motion layer: Lenis smooth scrolling synced to GSAP ScrollTrigger, an arrival sequence, a
 * traveller of light that rides the road with your scroll, chapters that rise as you reach them,
 * and touch-aware hover physics. Reduced motion, or a missing library, leaves the page complete
 * and still.
 */
(() => {
  "use strict";

  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const fine = matchMedia("(hover: hover) and (pointer: fine)").matches;
  const { gsap, ScrollTrigger, Lenis } = window;
  const done = () => document.body.classList.remove("is-loading");

  if (reduced || !gsap || !ScrollTrigger) {
    done();
    $("#curtain")?.remove();
    return;
  }
  gsap.registerPlugin(ScrollTrigger);
  document.documentElement.classList.add("motion");

  /* ---------- Numbers that count ---------- */
  const counters = new WeakMap();
  window.DarbMotion = {
    count(el, value) {
      const to = Number(value);
      if (!Number.isFinite(to)) {
        el.textContent = value;
        return;
      }
      const from = counters.has(el) ? counters.get(el).v : Number(el.textContent) || 0;
      const obj = { v: from };
      counters.get(el)?.tween?.kill();
      const tween = gsap.to(obj, {
        v: to,
        duration: from === to ? 0 : 1.2,
        ease: "power3.out",
        onUpdate: () => (el.textContent = Math.round(obj.v)),
      });
      counters.set(el, { v: to, tween });
    },
    whyIn() {
      gsap.fromTo(
        "#why-view .eyebrow, #why-view h2, #why-view .lede",
        { opacity: 0, y: 24 },
        { opacity: 1, y: 0, duration: 1, stagger: 0.08, ease: "expo.out" },
      );
      gsap.fromTo(
        "#pillars li",
        { opacity: 0, y: 40, rotateX: 10, transformPerspective: 900 },
        { opacity: 1, y: 0, rotateX: 0, duration: 1.1, stagger: 0.07, ease: "expo.out", delay: 0.2 },
      );
      gsap.fromTo(
        "#why-view .why-grid > *, #why-view .focus",
        { opacity: 0, y: 30 },
        { opacity: 1, y: 0, duration: 1, stagger: 0.08, ease: "expo.out", delay: 0.6 },
      );
    },
    sheen(card) {
      if (!card) return;
      card.classList.remove("sheen");
      void card.offsetWidth;
      card.classList.add("sheen");
      gsap.fromTo(card, { scale: 0.985 }, { scale: 1, duration: 0.8, ease: "elastic.out(1, 0.5)" });
    },
  };

  /* ---------- Smooth scrolling, one clock ---------- */
  let lenis = null;
  if (Lenis && fine) {
    // Wheel and trackpad glide; touch keeps the phone's own scrolling, which is already smooth.
    lenis = new Lenis({ lerp: 0.09, smoothWheel: true, wheelMultiplier: 0.9 });
    lenis.on("scroll", ScrollTrigger.update);
    gsap.ticker.add((t) => lenis.raf(t * 1000));
    gsap.ticker.lagSmoothing(0);
    // In-page links glide too.
    document.addEventListener("click", (e) => {
      const a = e.target.closest('a[href^="#"]');
      if (!a) return;
      const target = $(a.getAttribute("href"));
      if (!target) return;
      e.preventDefault();
      lenis.scrollTo(target, { offset: -150, duration: 1.4 });
    });
    const native = Element.prototype.scrollIntoView;
    Element.prototype.scrollIntoView = function (opts) {
      if (!lenis || this.closest("#today-view")) return native.call(this, opts);
      lenis.scrollTo(this, { offset: -innerHeight / 2 + this.offsetHeight / 2, duration: 1.2 });
    };
  }

  /* ---------- Words that rise ---------- */
  function splitWords(el) {
    if (!el || el.dataset.split) return [];
    el.dataset.split = "1";
    el.setAttribute("aria-label", el.textContent.replace(/\s+/g, " ").trim());
    const words = [];
    const walk = (node) => {
      [...node.childNodes].forEach((child) => {
        if (child.nodeType === 3) {
          const frag = document.createDocumentFragment();
          child.textContent.split(/(\s+)/).forEach((part) => {
            if (!part) return;
            if (/^\s+$/.test(part)) {
              frag.append(part);
              return;
            }
            const outer = document.createElement("span");
            outer.className = "w";
            outer.setAttribute("aria-hidden", "true");
            const inner = document.createElement("span");
            inner.textContent = part;
            outer.append(inner);
            frag.append(outer);
            words.push(inner);
          });
          child.replaceWith(frag);
        } else if (child.nodeType === 1) walk(child);
      });
    };
    walk(el);
    return words;
  }

  /* ---------- Arrival ---------- */
  const intro = gsap.timeline({ defaults: { ease: "expo.out" } });
  const curtain = $("#curtain");
  const heroWords = splitWords($("#hero-title"));
  gsap.set(heroWords, { yPercent: 110, rotate: 4 });
  gsap.set([".hero .eyebrow", ".hero .lede", ".hero-stats > div", ".next", ".controls"], { opacity: 0, y: 26 });
  gsap.set(".dial", { opacity: 0, scale: 0.86, rotate: -18 });
  gsap.set(".top", { yPercent: -100 });
  intro
    .to("#curtain img", { opacity: 1, scale: 1, duration: 1, ease: "power3.out" }, 0)
    .to("#curtain line", { strokeDashoffset: 0, duration: 0.9, ease: "power2.inOut" }, 0.15)
    .to(curtain, { yPercent: -100, duration: 1.1, ease: "expo.inOut" }, 0.95)
    .add(done, 1.1)
    .to(".top", { yPercent: 0, duration: 1 }, 1.25)
    .to(".hero .eyebrow", { opacity: 1, y: 0, duration: 1 }, 1.3)
    .to(heroWords, { yPercent: 0, rotate: 0, duration: 1.2, stagger: 0.045 }, 1.35)
    .to(".dial", { opacity: 1, scale: 1, rotate: 0, duration: 1.8 }, 1.4)
    .to(".hero .lede", { opacity: 1, y: 0, duration: 1 }, 1.8)
    .to(".hero-stats > div", { opacity: 1, y: 0, duration: 0.9, stagger: 0.08 }, 1.9)
    .to(".next", { opacity: 1, y: 0, duration: 1 }, 2.1)
    .to(".controls", { opacity: 1, y: 0, duration: 0.8 }, 2.2)
    .add(() => curtain.remove());
  // The dial's arc and numbers start from zero, then sweep to where you are.
  const arc = $("#dial-arc");
  const target = arc.style.strokeDasharray;
  arc.style.transition = "none";
  arc.style.strokeDasharray = "0 100";
  intro.add(() => {
    arc.style.transition = "";
    arc.style.strokeDasharray = target;
    ["#pct", "#st-steps", "#st-streak", "#day-n", "#st-left"].forEach((s) => {
      const el = $(s);
      const v = Number(el.textContent);
      el.textContent = "0";
      counters.set(el, { v: 0 });
      window.DarbMotion.count(el, v);
    });
  }, 1.5);

  /* ---------- Scroll thread ---------- */
  gsap.to("#thread", {
    scaleX: 1,
    ease: "none",
    scrollTrigger: { start: 0, end: "max", scrub: 0.4 },
  });

  /* ---------- Hero depth ---------- */
  gsap.to(".dial", {
    yPercent: 18,
    rotate: 12,
    ease: "none",
    scrollTrigger: { trigger: ".hero", start: "top top", end: "bottom top", scrub: true },
  });
  gsap.to(".hero-copy", {
    yPercent: -8,
    opacity: 0.35,
    ease: "none",
    scrollTrigger: { trigger: ".hero", start: "40% top", end: "bottom top", scrub: true },
  });

  /* ---------- Chapters ---------- */
  $$(".stage").forEach((stage) => {
    const words = splitWords($(".stage-name", stage));
    gsap.set(words, { yPercent: 105 });
    gsap.set([$(".stage-n", stage), $(".stage-line", stage), $(".stage-bar", stage)], { opacity: 0, y: 18 });
    const cards = $$(".plan", stage);
    gsap.set(cards, { opacity: 0, y: 40, rotateX: 8, transformPerspective: 900, transformOrigin: "50% 0%" });
    ScrollTrigger.create({
      trigger: stage,
      start: "top 78%",
      once: true,
      onEnter: () => {
        const tl = gsap.timeline({ defaults: { ease: "expo.out" } });
        tl.to($(".stage-n", stage), { opacity: 1, y: 0, duration: 0.8 })
          .to(words, { yPercent: 0, duration: 1.1, stagger: 0.06 }, 0.05)
          .to([$(".stage-line", stage), $(".stage-bar", stage)], { opacity: 1, y: 0, duration: 0.9, stagger: 0.08 }, 0.2)
          .to(cards, { opacity: 1, y: 0, rotateX: 0, duration: 1.1, stagger: 0.07, clearProps: "transform" }, 0.25);
      },
    });
    // The node ignites as the reading line passes it.
    ScrollTrigger.create({
      trigger: stage,
      start: "top 55%",
      end: "bottom 55%",
      toggleClass: { targets: stage, className: "in-view" },
    });
    // A huge faint numeral drifts behind each chapter.
    gsap.fromTo(
      $(".ghost-n", stage),
      { yPercent: 30 },
      { yPercent: -30, ease: "none", scrollTrigger: { trigger: stage, start: "top bottom", end: "bottom top", scrub: true } },
    );
  });

  // Side cards settle in once.
  gsap.from(".side .card", {
    opacity: 0,
    y: 30,
    duration: 1,
    stagger: 0.1,
    ease: "expo.out",
    scrollTrigger: { trigger: ".side", start: "top 85%", once: true },
  });

  /* ---------- The traveller ---------- */
  // Gold is your progress; this light is your reading position, riding the same road.
  const base = $("#road-base");
  const traveler = $("#traveler");
  let travel = null;
  const place = (p) => {
    const len = base.getTotalLength?.() || 0;
    if (!len) return;
    const pt = base.getPointAtLength(len * p);
    traveler.setAttribute("cx", pt.x);
    traveler.setAttribute("cy", pt.y);
  };
  function wireTraveller() {
    travel?.kill();
    travel = ScrollTrigger.create({
      trigger: "#road",
      start: "top 55%",
      end: "bottom 55%",
      scrub: 0.6,
      onUpdate: (self) => place(self.progress),
    });
    place(travel.progress);
  }
  addEventListener("road:layout", () => {
    wireTraveller();
    ScrollTrigger.refresh();
  });
  // Opening or closing a plan changes the page's height.
  document.addEventListener("toggle", () => requestAnimationFrame(() => ScrollTrigger.refresh()), true);

  /* ---------- Hover physics (fine pointers only) ---------- */
  if (fine) {
    // Cards lean toward the pointer, with a light that follows it.
    document.addEventListener("pointermove", (e) => {
      const card = e.target.closest?.(".plan:not([open]), .next-item, .hero-stats > div");
      $$(".tilting").forEach((c) => c !== card && untilt(c));
      if (!card) return;
      const r = card.getBoundingClientRect();
      const x = (e.clientX - r.left) / r.width - 0.5;
      const y = (e.clientY - r.top) / r.height - 0.5;
      card.classList.add("tilting");
      card.style.setProperty("--mx", `${(x + 0.5) * 100}%`);
      card.style.setProperty("--my", `${(y + 0.5) * 100}%`);
      gsap.to(card, { rotateY: x * 6, rotateX: -y * 6, transformPerspective: 800, duration: 0.6, ease: "power3.out" });
    });
    const untilt = (c) => {
      c.classList.remove("tilting");
      gsap.to(c, { rotateY: 0, rotateX: 0, duration: 0.8, ease: "elastic.out(1, 0.6)" });
    };
    // Buttons pull gently toward the cursor.
    $$(".tabs button, .chips button, .tool-row button, .file, .star").forEach((b) => {
      b.addEventListener("pointermove", (e) => {
        const r = b.getBoundingClientRect();
        gsap.to(b, {
          x: (e.clientX - r.left - r.width / 2) * 0.25,
          y: (e.clientY - r.top - r.height / 2) * 0.3,
          duration: 0.4,
          ease: "power3.out",
        });
      });
      b.addEventListener("pointerleave", () => gsap.to(b, { x: 0, y: 0, duration: 0.7, ease: "elastic.out(1, 0.5)" }));
    });
    // A soft gold halo trails the cursor.
    const halo = $("#halo");
    const hx = gsap.quickTo(halo, "x", { duration: 0.5, ease: "power3.out" });
    const hy = gsap.quickTo(halo, "y", { duration: 0.5, ease: "power3.out" });
    addEventListener("pointermove", (e) => {
      halo.classList.add("on");
      hx(e.clientX);
      hy(e.clientY);
      halo.classList.toggle("big", !!e.target.closest?.("button, a, summary, label, input, textarea"));
    });
    document.addEventListener("pointerleave", () => halo.classList.remove("on"));
    // The hero's light leans toward the pointer.
    addEventListener("pointermove", (e) => {
      gsap.to(document.body, {
        "--lx": `${(e.clientX / innerWidth) * 100}%`,
        "--ly": `${(e.clientY / innerHeight) * 100}%`,
        duration: 1.2,
        ease: "power2.out",
      });
    });
  }

  /* ---------- Views keep the clock right ---------- */
  document.addEventListener("click", (e) => {
    if (e.target.closest(".tabs button")) requestAnimationFrame(() => ScrollTrigger.refresh());
  });

  document.fonts?.ready.then(() => ScrollTrigger.refresh());
  addEventListener("load", () => ScrollTrigger.refresh());
})();
