# Agent Intake — Self-Guided Training Modules

This folder holds the shared scaffold and the three self-guided HTML learning
modules for the **agent-intake** governance solution:

| Module | Audience | Focus |
|--------|----------|-------|
| Executive | Sponsors, risk & compliance leaders | **Why** the intake gate exists and what it changes |
| Admin | M365 / Power Platform administrators | **How** to configure and operate the gate |
| Developer | Makers and platform engineers | **How** to extend classification, flows, and handoffs |

`_scaffold.html` is the **design + interaction baseline** all three modules
copy. It is a single, fully self-contained HTML file: every byte of CSS, JS,
and graphics lives inline, so it opens by double-click and makes **zero external
requests** (required, because the FSI network blocks external CDNs and fonts).

> These modules are training material. They describe controls that **support
> compliance with** regulations such as FINRA Rule 3110, FINRA Rule 4511, and
> SEC Rule 17a-4. They do not, on their own, satisfy any regulation —
> implementation requires organizations to verify configuration against their
> own obligations.

---

## What a content author does

1. **Copy the scaffold** to your module name:
   ```powershell
   Copy-Item _scaffold.html module-executive.html   # or module-admin / module-developer
   ```
2. **Edit the page shell** — `<title>`, `<meta name="description">`, the hero
   (eyebrow / `<h1>` / tagline / objectives), and the footer text.
3. **Rebuild the nav** — make each `<li><a href="#id" data-nav>` point at one of
   your `<section id="id">` blocks. Add or remove links as your sections change.
4. **Compose with the components** — copy the demo blocks (each is preceded by a
   `USAGE:` HTML comment) and replace every `PLACEHOLDER` / `SECTION TITLE HERE`
   / lorem-ish string with real teaching content. Write for a reader who is
   **browsing alone** — generous on-screen explanation, no implied narrator.
5. **Keep `<style>` and `<script>` intact.** They are the shared design system
   and behavior layer. Do not move them to separate files and do not add any
   `http(s)://` asset reference.
6. **Delete the author helper notes** — the small dashed `.demo-note` lines and
   the `USAGE:` comments are guidance for you; remove them from the finished
   module (or leave the comments — they do not render).

### Hard rules (keep the file shippable)

- **Zero external requests.** No CDN, no Google Fonts, no `<img src="http…">`,
  no `<link href="http…">`, no `@import url(http…)`. All graphics are inline
  SVG; the font is a system stack.
- **Respect motion + theme preferences.** Animations are gated behind
  `prefers-reduced-motion`; theming follows `prefers-color-scheme` plus an
  explicit toggle. Both are already wired — do not break them.
- **Stay accessible.** Semantic landmarks, ARIA, keyboard support, and visible
  focus are built in. Keep one `<h1>` per page (the hero), keep heading order
  sane, and give every `aria-controls`/`id` pair a unique value.

### Verify before you ship

```powershell
# 1. No external asset references (only inert href="#…" anchors are allowed)
Select-String -Path .\module-executive.html -Pattern 'https?://'      # expect: no matches

# 2. (optional) Strict HTML validity — requires html5lib
python -c "import html5lib; html5lib.HTMLParser(strict=True).parse(open('module-executive.html',encoding='utf-8').read()); print('valid')"
```

Note: HTML comments may **not** contain a `--` (double-hyphen) run. The shared
class convention uses single hyphens for modifiers (`callout-warn`, not
`callout--warn`) and `__` for element parts (`callout__title`), so you can
reference any class freely inside a `USAGE:` comment.

---

## Component cheat-sheet

Every component below has a live demo and a `USAGE:` comment in `_scaffold.html`.
Invoke each with the exact class and/or `data-` attribute shown here so all
three modules stay visually and behaviorally consistent.

### Structure & navigation

| Component | Invoke with | Notes |
|-----------|-------------|-------|
| Sticky header | `<header class="site-header">` | Contains the nav and the progress track. |
| Scroll-progress bar | `<div class="progress-track" role="progressbar">` wrapping `<div class="progress-bar" id="progressBar">` | `id="progressBar"` is **required** — the JS sets its width and the track's `aria-valuenow`. |
| Nav link (auto-highlight) | `<a href="#section-id" data-nav>` | `data-nav` opts the link into active-section highlighting on scroll. The `href` must match a `<section id>`. |
| Brand lockup | `<a class="brand">` | Inline SVG shield + circuit motif; edit the label text. |
| Dark-mode toggle | `<button id="themeToggle" class="theme-toggle">` | `id="themeToggle"` is **required**. Swaps sun/moon icon, updates `aria-pressed`, persists choice in `localStorage`. |
| Section wrapper | `<section id="…" class="section">` | Add `section-tint` for the alternating tinted background. Add `scroll-margin-top` is already handled. |

### Headings & hero

| Component | Invoke with | Notes |
|-----------|-------------|-------|
| Hero / intro | `<section class="hero" id="overview">` | One `<h1>` per page lives here. |
| "What you'll learn" objectives | `<div class="objectives">` with a `<ul>` of checkmarked `<li>` | List 3–5 action-oriented outcomes. Mirror these in the closing takeaways. |
| Eyebrow label | `<span class="eyebrow">` | Small uppercase label above an `<h2>`. |
| Section title | `<h2>` inside `.section` | |
| Lede paragraph | `<p class="lede">` | One-paragraph section intro. |
| Subsection heading | `<h3 class="subhead">` | Blue left-border subheading. |
| Buttons | `<a class="btn btn-primary">` / `<a class="btn btn-ghost">` | `btn-ghost` reads on the hero gradient. |

### Teaching visuals & motion

| Component | Invoke with | Notes |
|-----------|-------------|-------|
| Animated SVG diagram | `<figure class="diagram">` containing `<svg … data-animate-svg>` | `data-animate-svg` makes the JS add `.animate` when the diagram scrolls into view, which fires the CSS keyframes. Always include a `<figcaption>` so it reads without motion. |
| Pipeline diagram (Figure A) | `<g class="pl-node" style="--d:0.5s">` nodes; `.pl-track`, `.pl-progress`, `.pl-token`, `.pl-ring` | Left-to-right process with a drawing line, a traveling token, and staggered node pops. Set each node's entrance delay with inline `--d`. |
| Classification fork (Figure B) | `<g class="fk-box" style="--d:0.55s">`; `.fk-path`, `.fk-title`, `.fk-desc`, `.fk-input` | One input branching to several paths. Stagger boxes/paths with inline `--d`. |
| Scroll-reveal | add `data-reveal` to **any** element | Fades + slides the element in once on scroll (IntersectionObserver). Stagger siblings with inline `style="--reveal-delay:0.15s"`. |

### Content blocks

| Component | Invoke with | Notes |
|-----------|-------------|-------|
| Explore card (expandable) | `<article class="explore-card">` → `<button class="explore-card__trigger" data-card-trigger aria-expanded="false" aria-controls="UID">` → `<div class="explore-card__body"><div class="explore-card__bodyinner"><div class="explore-card__detail" id="UID">` | `data-card-trigger` wires the toggle. The trigger is a real `<button>`, so `Enter`/`Space` work. Give each `aria-controls`/`id` a **unique** value. Card parts: `__icon`, `__head`, `__chev`. |
| Card grid | `<div class="card-grid">` | Auto-fit responsive grid used by cards and stats. |
| Info callout | `<aside class="callout callout-info" role="note">` | Neutral tip or inline definition (blue). |
| Warning callout | `<aside class="callout callout-warn" role="note">` | Caution / gotcha (amber). |
| Regulation reference | `<aside class="callout callout-reg" role="note">` | Cite the rule by name + section (e.g. "FINRA Rule 3110"). Use "supports compliance with" / "helps meet" — never "ensures", "guarantees", or "will prevent". Parts for all callouts: `callout__icon`, `callout__title`, `callout__body`. |
| Timeline / stepper | `<ol class="timeline">` → `<li>` each starting with `<span class="step-dot">N</span>` then `<h3>` + `<p>` | Ordered sequence (lifecycle, runbook). |
| Stat / metric block | `<div class="stat-grid">` → `<div class="stat">` with `<span class="stat__num">` + `<span class="stat__label">` | Keep numbers honest and sourced. |
| Inline code | `<code class="code">fsi_intakedecisionlog</code>` | Literal identifiers. |
| Keyword pill | `<span class="kw">decision pack</span>` | Emphasised domain term. |
| Keyboard key | `<kbd class="kbd">Ctrl</kbd>` | |
| Code block | `<pre class="codeblock"><code>…</code></pre>` | Multi-line snippet. |
| Key takeaways | `<div class="takeaways">` with `<h3>` + checkmarked `<ul>` | Closing recap; mirror the hero objectives. |
| Footer | `<footer class="site-footer">` | Lightweight; edit the text. |
| Author helper note | `<p class="demo-note">` | Dashed scaffolding hint — **delete from finished modules.** |

### `data-` attributes & required IDs (the JS contract)

| Hook | Where | Effect |
|------|-------|--------|
| `data-nav` | nav `<a>` | Active-section highlight on scroll (also sets `aria-current`). |
| `data-reveal` | any element | Reveal on scroll; stagger with `style="--reveal-delay:Xs"`. |
| `data-animate-svg` | the `<svg>` (or an ancestor) | Adds `.animate` when in view to start diagram keyframes. |
| `data-card-trigger` | explore-card `<button>` | Toggles expand/collapse + `aria-expanded`. |
| `id="progressBar"` | progress bar `<div>` | Required — JS updates its width. |
| `id="themeToggle"` | toggle `<button>` | Required — JS wires theme switching. |
| `style="--reveal-delay:Xs"` | element with `data-reveal` | Per-element reveal delay (stagger). |
| `style="--d:Xs"` | `.pl-node` / `.fk-box` / `.fk-path` | Per-node SVG animation delay (stagger). |

### Theming

- The full palette is defined as CSS custom properties on `:root`
  (`--brand-primary` `#0078D4`, `--brand-accent` `#007A7E`, plus surface/text/
  callout/code tokens). Prefer these tokens over hard-coded colors.
- Dark mode resolves in three layers: light tokens by default →
  `@media (prefers-color-scheme: dark)` for system preference → an explicit
  `:root[data-theme="dark"]` set by the toggle (the explicit choice wins).
- When adjusting brand color, change the tokens — not individual rules — so
  light and dark stay aligned.

### Accessibility checklist (per module)

- One `<h1>`; logical heading order; landmarks (`header`/`nav`/`main`/`footer`).
- Every `aria-controls` points at a unique element `id`.
- All interactive controls are reachable by keyboard with a visible focus ring.
- Color contrast meets WCAG AA (the supplied tokens are calibrated for it).
- Animations are curtailed under `prefers-reduced-motion` — do not add motion
  that ignores it.
