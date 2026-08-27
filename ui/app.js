(() => {
  const $ = (id) => document.getElementById(id);
  const state = {
    schema: null,
    skills: [],
    constraints: [],
    search: {
      gear: true,
      rares: true,
      jewels: true,
      gems: true,
      flasks: true,
      tree: true,
      ascendancy: true,
      cluster: true,
      timeless: true,
    },
    running: false,
    abort: null,
  };

  const LOCAL = location.hostname === "127.0.0.1" || location.hostname === "localhost";
  const REMOTE = !LOCAL;
  const ON_PAGES = location.hostname.endsWith("github.io");

  const EXTRA_DIMS = [
    { id: "rares", label: "Rares générés" },
  ];

  function fmt(n, unit) {
    if (n == null || Number.isNaN(Number(n))) return "—";
    const v = Number(n);
    if (unit === "percent") return `${Math.round(v * 10) / 10} %`;
    if (unit === "multiplier") return `×${Math.round(v * 100) / 100}`;
    if (unit === "dps" || Math.abs(v) >= 1000) {
      return Math.round(v).toLocaleString("fr-FR");
    }
    return (Math.round(v * 100) / 100).toLocaleString("fr-FR");
  }

  function statMeta(key) {
    return (state.schema && state.schema.stats.find((s) => s.key === key)) || { key, label: key, unit: "number" };
  }

  function repoSlug() {
    const js = location.pathname.match(/\/gh\/([^/]+)\/([^/@]+)/);
    if (location.hostname.includes("jsdelivr.net") && js) return `${js[1]}/${js[2]}`;
    if (ON_PAGES) {
      const user = location.hostname.split(".")[0];
      const repo = location.pathname.split("/").filter(Boolean)[0];
      if (user && repo) return `${user}/${repo}`;
    }
    return "Vivosjerome/PathOfExileBuilder";
  }

  function schemaUrl() {
    if (LOCAL) return "/api/schema";
    if (ON_PAGES) return "../schema.json";
    return "../docs/schema.json";
  }

  async function loadHealth() {
    if (REMOTE) {
      const el = $("health");
      el.textContent = "GitHub Actions · PoB";
      el.className = "health ok";
      $("run").textContent = "Lancer sur GitHub";
      $("reload-latest").hidden = false;
      $("cancel").hidden = true;
      $("dry-run").checked = true;
      return;
    }
    try {
      const h = await (await fetch("/api/health")).json();
      const el = $("health");
      el.textContent = h.ok ? "moteur prêt" : (h.error || "moteur indisponible");
      el.className = "health " + (h.ok ? "ok" : "bad");
    } catch {
      $("health").textContent = "serveur hors ligne";
      $("health").className = "health bad";
    }
  }

  function fillSelect(el, items, getValue, getLabel, selected) {
    el.textContent = "";
    for (const item of items) {
      const opt = document.createElement("option");
      opt.value = getValue(item);
      opt.textContent = getLabel(item);
      if (opt.value === selected) opt.selected = true;
      el.appendChild(opt);
    }
  }

  function syncAscendancy() {
    const cls = state.schema.classes.find((c) => c.name === $("class").value);
    const list = (cls && cls.ascendancies) || [];
    const keep = $("ascendancy").value;
    fillSelect($("ascendancy"), list, (x) => x, (x) => x, list.includes(keep) ? keep : list[0]);
  }

  function renderPresets() {
    const box = $("presets");
    box.textContent = "";
    for (const preset of state.schema.presets) {
      const b = document.createElement("button");
      b.type = "button";
      b.textContent = preset.label;
      b.addEventListener("click", () => {
        for (const [key, value] of Object.entries(preset.min || {})) {
          upsertConstraint(key, { min: value });
        }
        for (const [key, value] of Object.entries(preset.max || {})) {
          upsertConstraint(key, { max: value });
        }
        renderConstraints();
      });
      box.appendChild(b);
    }
  }

  function upsertConstraint(key, patch) {
    let row = state.constraints.find((c) => c.key === key);
    if (!row) {
      row = { key, min: "", max: "" };
      state.constraints.push(row);
    }
    if (patch.min != null) row.min = patch.min;
    if (patch.max != null) row.max = patch.max;
  }

  function renderConstraints() {
    const box = $("constraints");
    box.textContent = "";
    for (const row of state.constraints) {
      const meta = statMeta(row.key);
      const wrap = document.createElement("div");
      wrap.className = "constraint";
      const name = document.createElement("div");
      name.className = "name";
      name.textContent = meta.label;
      const min = document.createElement("input");
      min.type = "number";
      min.step = "any";
      min.placeholder = "min";
      min.value = row.min === "" || row.min == null ? "" : row.min;
      min.addEventListener("input", () => { row.min = min.value; });
      const max = document.createElement("input");
      max.type = "number";
      max.step = "any";
      max.placeholder = "max";
      max.value = row.max === "" || row.max == null ? "" : row.max;
      max.addEventListener("input", () => { row.max = max.value; });
      const x = document.createElement("button");
      x.type = "button";
      x.className = "x";
      x.textContent = "×";
      x.addEventListener("click", () => {
        state.constraints = state.constraints.filter((c) => c !== row);
        renderConstraints();
      });
      wrap.append(name, min, max, x);
      box.appendChild(wrap);
    }
  }

  function renderDimensions() {
    const box = $("dimensions");
    box.textContent = "";
    const dims = [...EXTRA_DIMS, ...state.schema.dimensions];
    for (const dim of dims) {
      const b = document.createElement("button");
      b.type = "button";
      b.textContent = dim.label.replace(/\s*\(.*/, "");
      b.className = state.search[dim.id] ? "on" : "";
      if (dim.id === "gear") {
        b.className = "on";
        b.title = "Le stuff est toujours cherché";
      } else {
        b.addEventListener("click", () => {
          state.search[dim.id] = !state.search[dim.id];
          b.className = state.search[dim.id] ? "on" : "";
        });
      }
      box.appendChild(b);
    }
  }

  function bindSkillCombo() {
    const input = $("skill");
    const menu = $("skill-list");
    let selected = -1;
    const hide = () => { menu.hidden = true; selected = -1; };
    const show = (q) => {
      const query = (q || "").toLowerCase();
      const hits = [];
      for (const skill of state.skills) {
        if (!query || skill.name.toLowerCase().includes(query)) hits.push(skill);
        if (hits.length >= 12) break;
      }
      menu.textContent = "";
      hits.forEach((skill, i) => {
        const b = document.createElement("button");
        b.type = "button";
        b.textContent = skill.name;
        b.addEventListener("mousedown", (ev) => {
          ev.preventDefault();
          input.value = skill.name;
          hide();
        });
        if (i === selected) b.setAttribute("aria-selected", "true");
        menu.appendChild(b);
      });
      menu.hidden = hits.length === 0;
    };
    input.addEventListener("focus", () => show(input.value));
    input.addEventListener("input", () => show(input.value));
    input.addEventListener("blur", () => setTimeout(hide, 120));
    input.addEventListener("keydown", (ev) => {
      if (menu.hidden) return;
      const buttons = [...menu.querySelectorAll("button")];
      if (ev.key === "ArrowDown") {
        ev.preventDefault();
        selected = Math.min(buttons.length - 1, selected + 1);
        show(input.value);
      } else if (ev.key === "ArrowUp") {
        ev.preventDefault();
        selected = Math.max(0, selected - 1);
        show(input.value);
      } else if (ev.key === "Enter" && selected >= 0 && buttons[selected]) {
        ev.preventDefault();
        input.value = buttons[selected].textContent;
        hide();
      } else if (ev.key === "Escape") hide();
    });
  }

  function definition() {
    const min = {};
    const max = {};
    for (const row of state.constraints) {
      if (row.min !== "" && row.min != null) min[row.key] = Number(row.min);
      if (row.max !== "" && row.max != null) max[row.key] = Number(row.max);
    }
    return {
      class: $("class").value,
      ascendancy: $("ascendancy").value,
      level: Number($("level").value) || 90,
      skill: {
        name: $("skill").value.trim(),
        level: Number($("skill-level").value) || 20,
        quality: Number($("skill-quality").value) || 20,
      },
      objective: $("objective").value,
      constraints: { min, max },
      search: {
        ...state.search,
        beamSize: Number($("beam").value) || 100,
        dryRun: $("dry-run").checked === true,
      },
    };
  }

  function appendLog(line) {
    const el = $("log");
    el.textContent += line + "\n";
    if (el.textContent.length > 120000) {
      el.textContent = el.textContent.slice(-80000);
    }
    el.scrollTop = el.scrollHeight;
    const m = line.match(/^(.+) optimization$/);
    if (m) $("status").textContent = m[1];
    else if (line.startsWith("SEARCH COMPLETE") || line.startsWith("COMPLETE BUILD")) {
      $("status").textContent = "Terminé";
    }
  }

  function li(slot, name) {
    const item = document.createElement("li");
    const a = document.createElement("span");
    a.className = "slot";
    a.textContent = slot || "";
    const b = document.createElement("span");
    b.textContent = name || "";
    item.append(a, b);
    return item;
  }

  function section(title, rows, span2) {
    const wrap = document.createElement("div");
    if (span2) wrap.className = "span2";
    const h = document.createElement("h3");
    h.textContent = title;
    const ul = document.createElement("ul");
    if (!rows.length) {
      const empty = document.createElement("li");
      empty.textContent = "—";
      ul.appendChild(empty);
    } else {
      for (const row of rows) ul.appendChild(li(row.slot || row.group || "", row.name));
    }
    wrap.append(h, ul);
    return wrap;
  }

  function renderResult(result) {
    const stats = (result.verified && result.verified.stats) || {};
    const complete = result.complete || {};
    const metrics = result.metrics || {};
    const hero = $("hero");
    hero.hidden = false;
    hero.textContent = "";
    const cards = [
      ["DPS", fmt(stats.CombinedDPS, "dps"), "wide"],
      ["Vie", fmt(stats.Life), ""],
      ["ES", fmt(stats.EnergyShield), ""],
      ["EHP", fmt(stats.TotalEHP), ""],
      ["Crit", `${fmt(stats.CritChance, "percent")}  ${fmt(stats.CritMultiplier, "multiplier")}`, "wide"],
    ];
    for (const [k, v, extra] of cards) {
      const d = document.createElement("div");
      d.className = "metric " + extra;
      d.innerHTML = "";
      const kk = document.createElement("div");
      kk.className = "k";
      kk.textContent = k;
      const vv = document.createElement("div");
      vv.className = "v";
      vv.textContent = v;
      d.append(kk, vv);
      hero.appendChild(d);
    }
    const res = document.createElement("div");
    res.className = "metric res wide";
    const rk = document.createElement("div");
    rk.className = "k";
    rk.textContent = "Résistances F / C / L / Chaos";
    const rv = document.createElement("div");
    rv.className = "v";
    const sf = document.createElement("span");
    sf.className = "f";
    sf.textContent = fmt(stats.FireResist, "percent");
    const sc = document.createElement("span");
    sc.className = "c";
    sc.textContent = fmt(stats.ColdResist, "percent");
    const sl = document.createElement("span");
    sl.className = "l";
    sl.textContent = fmt(stats.LightningResist, "percent");
    const sch = document.createElement("span");
    sch.textContent = fmt(stats.ChaosResist, "percent");
    rv.append(sf, sc, sl, sch);
    res.append(rk, rv);
    hero.appendChild(res);

    const extra = document.createElement("div");
    extra.className = "metric wide";
    const ek = document.createElement("div");
    ek.className = "k";
    ek.textContent = "Recherche";
    const ev = document.createElement("div");
    ev.className = "v";
    const bits = [];
    if (metrics.pobEvaluations != null) bits.push(`${metrics.pobEvaluations.toLocaleString("fr-FR")} evals`);
    if (metrics.seconds != null) bits.push(`${Math.round(metrics.seconds)} s`);
    if (result.verified && result.verified.feasible) bits.push("valide");
    ev.textContent = bits.join(" · ");
    extra.append(ek, ev);
    hero.appendChild(extra);

    const build = $("build");
    build.hidden = false;
    build.textContent = "";
    const gems = (complete.gems || []).map((g) => ({
      slot: g.support ? "support" : (g.group || "skill"),
      name: `${g.name || "?"} ${g.level || ""}/${g.quality || ""}`.trim(),
    }));
    const tree = (complete.tree || []).map((name) => ({ slot: "", name }));
    const ascend = (complete.ascendancyNotables || []).map((name) => ({ slot: complete.ascendancy || "", name }));
    build.append(
      section("Stuff", complete.gear || []),
      section("Flasks", complete.flasks || []),
      section("Gems / supports", gems),
      section("Jewels", complete.jewels || []),
      section("Ascendance", ascend),
      section("Passifs", tree, true),
    );
  }

  async function runViaGitHub() {
    const def = definition();
    const title = `[optimize] ${def.skill.name} · ${def.class} ${def.ascendancy}`;
    const body = [
      "PoB tournera dans GitHub Actions. Ferme cette page seulement après avoir cliqué *Submit new issue*.",
      "",
      "```json",
      JSON.stringify(def, null, 2),
      "```",
      "",
    ].join("\n");
    const url = `https://github.com/${repoSlug()}/issues/new?title=${encodeURIComponent(title)}&body=${encodeURIComponent(body)}`;
    $("status").textContent = "Confirme l’issue GitHub — Actions lance le vrai PoB.";
    $("log-wrap").open = true;
    appendLog("Le navigateur ne calcule pas le DPS. GitHub Actions exécute LuaJIT + Path of Building.");
    appendLog(def.search.dryRun ? "Mode test : index PoB seulement." : "Recherche complète : souvent 20–50 min.");
    appendLog("Quand le job est vert, clique « Dernier résultat » ou recharge cette page.");
    window.open(url, "_blank", "noopener");
  }

  async function loadLatest() {
    const slug = repoSlug();
    const candidates = LOCAL
      ? ["/api/latest"]
      : ON_PAGES
        ? ["../runs/latest.json"]
        : [
            `https://api.github.com/repos/${slug}/contents/docs/runs/latest.json?ref=main`,
            "../docs/runs/latest.json",
          ];
    try {
      let data = null;
      let lastErr = "pas encore de résultat publié";
      for (const url of candidates) {
        const headers = {};
        if (url.includes("api.github.com")) headers.Accept = "application/vnd.github.raw+json";
        const res = await fetch(url, { cache: "no-store", headers });
        if (!res.ok) {
          lastErr = "pas encore de résultat publié";
          continue;
        }
        data = await res.json();
        break;
      }
      if (!data) throw new Error(lastErr);
      const result = data.result || data;
      if (!result || result.pending) throw new Error("en attente");
      renderResult(result);
      $("status").textContent = "Dernier run GitHub Actions";
      $("log-wrap").open = true;
      if (data.log) {
        $("log").textContent = data.log;
      } else {
        appendLog("Résultat chargé depuis runs/latest.json");
      }
    } catch (err) {
      $("status").textContent = String(err.message || err);
    }
  }

  async function run() {
    if (REMOTE) {
      await runViaGitHub();
      return;
    }
    state.running = true;
    $("run").disabled = true;
    $("cancel").hidden = false;
    $("status").textContent = "Lancement…";
    $("log").textContent = "";
    $("log-wrap").open = true;
    $("hero").hidden = true;
    $("build").hidden = true;
    const controller = new AbortController();
    state.abort = controller;
    try {
      const res = await fetch("/api/generate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(definition()),
        signal: controller.signal,
      });
      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buf = "";
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buf += decoder.decode(value, { stream: true });
        const parts = buf.split("\n");
        buf = parts.pop() || "";
        for (const line of parts) {
          if (!line.trim()) continue;
          let msg;
          try { msg = JSON.parse(line); } catch { continue; }
          if (msg.t === "log") appendLog(msg.line);
          if (msg.t === "error") {
            $("status").textContent = msg.error;
            appendLog(msg.error);
          }
          if (msg.t === "result" && msg.result) {
            renderResult(msg.result);
            const s = msg.result.metrics || {};
            $("status").textContent = s.seconds
              ? `Terminé · ${Math.round(s.seconds)} s · ${fmt(s.pobEvaluations)} evals`
              : "Terminé";
          }
        }
      }
    } catch (err) {
      if (err.name !== "AbortError") {
        $("status").textContent = String(err.message || err);
        appendLog(String(err.message || err));
      } else {
        $("status").textContent = "Arrêté";
      }
    } finally {
      state.running = false;
      state.abort = null;
      $("run").disabled = false;
      $("cancel").hidden = true;
      loadHealth();
    }
  }

  async function cancel() {
    if (state.abort) state.abort.abort();
    try { await fetch("/api/cancel", { method: "POST", body: "{}" }); } catch {}
    $("status").textContent = "Arrêté";
  }

  async function boot() {
    await loadHealth();
    const schema = await (await fetch(schemaUrl())).json();
    if (schema.error) {
      $("status").textContent = schema.error;
      return;
    }
    state.schema = schema;
    state.skills = schema.skills || [];
    fillSelect($("class"), schema.classes, (c) => c.name, (c) => c.name, "Witch");
    $("class").addEventListener("change", syncAscendancy);
    syncAscendancy();
    const elist = $("ascendancy");
    if ([...elist.options].some((o) => o.value === "Elementalist")) elist.value = "Elementalist";
    fillSelect($("objective"), schema.objectives, (o) => o.id, (o) => o.label, "MAX_DPS");
    const add = $("add-stat");
    add.textContent = "";
    for (const group of schema.groups) {
      const og = document.createElement("optgroup");
      og.label = group.label;
      for (const stat of schema.stats.filter((s) => s.group === group.id)) {
        const opt = document.createElement("option");
        opt.value = stat.key;
        opt.textContent = stat.hint ? `${stat.label} (${stat.hint})` : stat.label;
        og.appendChild(opt);
      }
      add.appendChild(og);
    }
    renderPresets();
    upsertConstraint("FireResist", { min: 75 });
    upsertConstraint("ColdResist", { min: 75 });
    upsertConstraint("LightningResist", { min: 75 });
    renderConstraints();
    renderDimensions();
    bindSkillCombo();
    $("beam").addEventListener("input", () => { $("beam-val").textContent = $("beam").value; });
    $("add-constraint").addEventListener("click", () => {
      upsertConstraint($("add-stat").value, {});
      renderConstraints();
    });
    $("run").addEventListener("click", run);
    $("cancel").addEventListener("click", cancel);
    $("reload-latest").addEventListener("click", loadLatest);
    $("status").textContent = REMOTE ? "Prêt — PoB tournera sur GitHub Actions" : "Prêt";
    if (REMOTE) loadLatest().catch(() => {});
  }

  boot().catch((err) => {
    $("status").textContent = String(err);
    $("health").className = "health bad";
  });
})();
