/* WhisperFly site interactions. Plain JS, no dependencies. */
(() => {
  "use strict";

  const reduced = document.documentElement.classList.contains("reduced");
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

  /* ── Nav border once the page scrolls ───────────────── */
  const nav = $(".nav");
  const onScrollNav = () => nav.classList.toggle("is-scrolled", window.scrollY > 8);
  window.addEventListener("scroll", onScrollNav, { passive: true });
  onScrollNav();

  /* ── Scroll reveal, staggered within a grid ─────────── */
  const reveals = $$(".reveal");
  reveals.forEach((el) => {
    const siblings = Array.from(el.parentElement.children).filter((c) => c.classList.contains("reveal"));
    const index = siblings.indexOf(el);
    if (siblings.length > 2 && index > 0) el.style.setProperty("--d", `${Math.min(index, 6) * 0.07}s`);
  });
  if ("IntersectionObserver" in window && !reduced) {
    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => {
        if (e.isIntersecting) { e.target.classList.add("is-visible"); io.unobserve(e.target); }
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
    reveals.forEach((el) => io.observe(el));
  } else {
    reveals.forEach((el) => el.classList.add("is-visible"));
  }

  /* ── Statement: words light up as you scroll ────────── */
  const statement = $("#statement");
  if (statement) {
    const words = statement.textContent.trim().split(/\s+/);
    statement.innerHTML = words.map((w) => `<span class="w">${w}</span>`).join(" ");
    const spans = $$(".w", statement);
    if (reduced) {
      spans.forEach((s) => s.classList.add("is-on"));
    } else {
      let ticking = false;
      const update = () => {
        ticking = false;
        const r = statement.getBoundingClientRect();
        const vh = window.innerHeight;
        const start = vh * 0.85;            // first word lights when the top is here
        const end = vh * 0.35;              // last word lights when the bottom is here
        const progress = (start - r.top) / (start - end + r.height);
        const lit = Math.round(Math.max(0, Math.min(1, progress)) * spans.length);
        spans.forEach((s, i) => s.classList.toggle("is-on", i < lit));
      };
      const onScroll = () => { if (!ticking) { ticking = true; requestAnimationFrame(update); } };
      window.addEventListener("scroll", onScroll, { passive: true });
      window.addEventListener("resize", onScroll);
      update();
    }
  }

  /* ── "Hello" in many languages ──────────────────────── */
  const hello = $(".hello");
  if (hello && !reduced) {
    const items = $$("span", hello);
    let i = 0;
    items[0].classList.add("is-on");
    setInterval(() => {
      if (document.hidden) return;
      const prev = items[i];
      i = (i + 1) % items.length;
      prev.classList.remove("is-on");
      prev.classList.add("is-out");
      setTimeout(() => prev.classList.remove("is-out"), 650);
      items[i].classList.add("is-on");
    }, 1700);
  }

  /* ── AI rewrite modes ───────────────────────────────── */
  const REWRITES = {
    cleanup: {
      label: "WhisperFly wrote",
      text: "I think we should probably ship the update on Friday if the tests pass, and then tell Sasha.",
      hint: "Removes filler words and repeats, fixes casing and punctuation, keeps your wording.",
    },
    punctuate: {
      label: "WhisperFly wrote",
      text: "Um, so I think we should, uh, probably ship the update on Friday if the, the tests pass, you know, and then tell Sasha.",
      hint: "Only adds punctuation and capitals. Every word you said stays exactly as you said it.",
    },
    professional: {
      label: "WhisperFly wrote",
      text: "I recommend we ship the update on Friday, provided the tests pass, and then brief Sasha.",
      hint: "Rewrites into a clear, polite tone for email and work chat.",
    },
    translate: {
      label: "Translated to Russian",
      text: "Думаю, обновление стоит выпустить в пятницу, если тесты пройдут, а потом сообщить Саше.",
      hint: "Speak in one language, get text in any other. The target language is up to you.",
    },
    custom: {
      label: "Instruction: “Write it as a to-do list”",
      text: "☐ Ship the update on Friday (if tests pass)\n☐ Tell Sasha",
      hint: "Write your own instruction and WhisperFly follows it on every dictation.",
    },
  };
  const rwButtons = $$("#rewrite [data-mode]");
  const rwOut = $("#rewrite-out");
  const rwLabel = $("#rewrite-label");
  const rwHint = $("#rewrite-hint");
  let rwTimer = null;
  const selectMode = (button, focus = false) => {
    const mode = REWRITES[button.dataset.mode];
    rwButtons.forEach((b) => {
      const on = b === button;
      b.setAttribute("aria-selected", String(on));
      b.tabIndex = on ? 0 : -1;
    });
    if (focus) button.focus();
    clearTimeout(rwTimer);
    rwOut.classList.add("is-swapping");
    rwTimer = setTimeout(() => {
      rwOut.textContent = "";
      mode.text.split("\n").forEach((line, i) => {
        if (i) rwOut.appendChild(document.createElement("br"));
        rwOut.appendChild(document.createTextNode(line));
      });
      rwLabel.textContent = mode.label;
      rwHint.textContent = mode.hint;
      rwOut.classList.remove("is-swapping");
    }, reduced ? 0 : 220);
  };
  rwButtons.forEach((b, i) => {
    b.tabIndex = i === 0 ? 0 : -1;
    b.addEventListener("click", () => selectMode(b));
  });
  arrowKeys(rwButtons, (b) => selectMode(b, true));

  /* ── Install tabs ───────────────────────────────────── */
  const tabButtons = $$(".install [role=tab]");
  const selectTab = (button, focus = false) => {
    tabButtons.forEach((b) => {
      const on = b === button;
      b.setAttribute("aria-selected", String(on));
      b.tabIndex = on ? 0 : -1;
      $("#" + b.getAttribute("aria-controls")).hidden = !on;
    });
    if (focus) button.focus();
  };
  tabButtons.forEach((b, i) => {
    b.tabIndex = i === 0 ? 0 : -1;
    b.addEventListener("click", () => selectTab(b));
  });
  arrowKeys(tabButtons, (b) => selectTab(b, true));

  function arrowKeys(buttons, select) {
    buttons.forEach((b, i) => b.addEventListener("keydown", (e) => {
      const step = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
      if (!step) return;
      e.preventDefault();
      select(buttons[(i + step + buttons.length) % buttons.length]);
    }));
  }

  /* ── Copy buttons ───────────────────────────────────── */
  $$(".code__copy").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const text = btn.dataset.copy;
      try {
        await navigator.clipboard.writeText(text);
      } catch {
        const ta = document.createElement("textarea");
        ta.value = text; ta.style.position = "fixed"; ta.style.opacity = "0";
        document.body.appendChild(ta); ta.select();
        try { document.execCommand("copy"); } catch { /* nothing else to try */ }
        ta.remove();
      }
      btn.textContent = "Copied";
      btn.classList.add("is-done");
      setTimeout(() => { btn.textContent = "Copy"; btn.classList.remove("is-done"); }, 1600);
    });
  });

  /* ── Hero demo ──────────────────────────────────────── */
  const demo = $("#demo");
  if (demo) runDemo();

  function runDemo() {
    const SCRIPT = [
      {
        said: "um so can we move the launch to friday the build is uh ready",
        engine: "Groq · Whisper Large v3 Turbo",
        mode: "Cleanup",
        typed: "Can we move the launch to Friday? The build is ready.",
      },
      {
        said: "напомни команде что демо в пять",
        engine: "Gemini 3.5 Transcribe",
        mode: "Translate → English",
        typed: "Reminder for the team: the demo is at 5.",
      },
      {
        said: "tell sasha the kubernetes migration is done and the swiftui fixes are next",
        engine: "Groq · Whisper Large v3 Turbo",
        mode: "Professional",
        typed: "Sasha, the Kubernetes migration is complete. The SwiftUI fixes are next.",
      },
    ];

    const pill = $("#demo-pill");
    const screen = $(".mac__screen", demo);
    const typed = $("#demo-typed");
    const line = $("#demo-text");
    const caret = $(".caret", line);
    const speech = $("#demo-speech");
    const fn = $("#demo-fn");
    const menuIcon = $("#demo-menu-icon");
    const timer = $("#demo-timer");
    const engineLabel = $("#demo-engine");
    const modeLabel = $("#demo-mode");
    const steps = $$("#demo-steps [data-step]");

    // Waveform bars, newest on the right like the app
    const wave = $("#demo-wave");
    const BAR_COUNT = 26;
    const bars = Array.from({ length: BAR_COUNT }, (_, i) => {
      const b = document.createElement("i");
      b.style.opacity = String(0.35 + 0.65 * (i / BAR_COUNT));
      wave.appendChild(b);
      return b;
    });
    const levels = new Array(BAR_COUNT).fill(0.06);

    if (reduced) {
      typed.textContent = SCRIPT[0].typed;
      return;
    }

    // Pause the loop while the demo is off screen or the tab is hidden.
    let visible = false;
    new IntersectionObserver(([e]) => { visible = e.isIntersecting; }, { threshold: 0.15 }).observe(demo);
    const active = () => visible && !document.hidden;

    const sleep = (ms) => new Promise((resolve) => {
      let left = ms;
      const tick = () => {
        if (active()) left -= 50;
        if (left <= 0) resolve(); else setTimeout(tick, 50);
      };
      setTimeout(tick, 50);
    });

    const setStep = (name) => {
      const order = ["hold", "speak", "release", "done"];
      const upTo = order.indexOf(name);
      steps.forEach((s) => s.classList.toggle("is-on", order.indexOf(s.dataset.step) <= upTo && upTo >= 0));
    };

    // Keep the pill just under the caret, as the app does.
    const placePill = () => {
      const sr = screen.getBoundingClientRect();
      const cr = caret.getBoundingClientRect();
      const em = parseFloat(getComputedStyle(screen).fontSize);
      const top = cr.bottom - sr.top + em * 0.7;
      pill.style.top = `${Math.min(top, sr.height - em * 6.5)}px`;
    };
    // The pill hugs whatever it currently shows, like the app's capsule.
    const pillBody = $(".pill", pill);
    const setState = (state) => {
      pill.dataset.state = state;
      const content = $(`.pill__content--${state}`, pill);
      if (!content) return;
      const em = parseFloat(getComputedStyle(screen).fontSize);
      pillBody.style.width = `${content.offsetWidth + em * 2}px`;
    };
    window.addEventListener("resize", () => { placePill(); setState(pill.dataset.state); });

    // Audio level simulation
    let speaking = false;
    let recording = false;
    let syllable = 0;
    setInterval(() => {
      if (!recording || !active()) return;
      syllable += 0.55 + Math.random() * 0.5;
      const envelope = speaking ? 0.45 + 0.55 * Math.abs(Math.sin(syllable)) : 0.08;
      const level = speaking ? Math.max(0.12, envelope * (0.55 + Math.random() * 0.45)) : 0.05 + Math.random() * 0.05;
      levels.shift(); levels.push(level);
      bars.forEach((b, i) => { b.style.height = `${Math.round(levels[i] * 100)}%`; });
    }, 75);

    let startedAt = 0;
    setInterval(() => {
      if (!recording) return;
      const s = Math.floor((performance.now() - startedAt) / 1000);
      timer.textContent = `0:${String(s).padStart(2, "0")}`;
    }, 200);

    const showSpeech = async (text) => {
      speech.innerHTML = text.split(" ").map((w) => `<span class="w">${w}</span>`).join(" ");
      speech.classList.add("is-on");
      const words = $$(".w", speech);
      for (const w of words) {
        w.classList.add("is-on");
        await sleep(150 + Math.random() * 110);
      }
    };

    const typeText = async (text, prefix) => {
      for (let i = 1; i <= text.length; i++) {
        typed.textContent = prefix + text.slice(0, i);
        if (i % 3 === 0) placePill();
        await sleep(16);
      }
    };

    (async function loop() {
      let n = 0;
      let doc = "";
      await sleep(700);
      for (;;) {
        const step = SCRIPT[n % SCRIPT.length];
        if (n % SCRIPT.length === 0 && n > 0) {
          // Start a fresh note
          typed.textContent = "";
          doc = "";
          await sleep(500);
        }
        placePill();

        // Hold fn
        setStep("hold");
        fn.classList.add("is-down");
        menuIcon.classList.add("is-live");
        engineLabel.textContent = step.engine;
        modeLabel.textContent = step.mode;
        levels.fill(0.06);
        startedAt = performance.now();
        timer.textContent = "0:00";
        recording = true;
        setState("recording");
        await sleep(600);

        // Speak
        setStep("speak");
        speaking = true;
        await showSpeech(step.said);
        speaking = false;
        await sleep(450);

        // Let go
        setStep("release");
        fn.classList.remove("is-down");
        recording = false;
        setState("transcribing");
        await sleep(1100);
        speech.classList.remove("is-on");
        setState("rewriting");
        await sleep(1000);

        // Text appears
        menuIcon.classList.remove("is-live");
        const prefix = doc ? doc + " " : "";
        await typeText(step.typed, prefix);
        doc = prefix + step.typed;
        setState("done");
        setStep("done");
        await sleep(1500);

        setState("idle");
        setStep("none");
        await sleep(1400);
        n++;
      }
    })();
  }
})();
