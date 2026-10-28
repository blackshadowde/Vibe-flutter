// Vibe site motion. Without GSAP or with "reduce motion" on, every section
// simply shows its finished state.
(() => {
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];

  // nav turns glassy once you scroll
  const nav = $('#nav');
  const onScroll = () => nav.classList.toggle('scrolled', window.scrollY > 20);
  onScroll();
  window.addEventListener('scroll', onScroll, { passive: true });

  // key blocks for the strict encryption scene (30 messages, a key every 10)
  const track = $('.keytrack');
  for (let i = 0; i < 30; i++) track.appendChild(document.createElement('i'));
  const blocks = $$('.keytrack i');
  const keyColors = ['#5865F2', '#23A55A', '#EB459E'];

  // features: one chapter at a time while the section scrolls past
  const chapters = $('.chapters');
  const items = $$('.ch-list li');
  const scenes = $$('.scene');
  let current = 0;
  const onChapters = () => {
    const r = chapters.getBoundingClientRect();
    const total = r.height - window.innerHeight;
    const p = Math.min(Math.max(-r.top / total, 0), 0.999);
    const i = Math.floor(p * items.length);
    if (i === current) return;
    current = i;
    items.forEach((el, k) => el.classList.toggle('on', k === i));
    scenes.forEach((el, k) => el.classList.toggle('on', k === i));
  };
  window.addEventListener('scroll', onChapters, { passive: true });
  onChapters();

  // iPhone: copy the source link, and point "Download IPA" at the newest build
  const SOURCE = 'https://raw.githubusercontent.com/blackshadowde/Vibe-flutter/Vibe/altstore.json';
  const copyBtn = $('#copy-source');
  copyBtn?.addEventListener('click', async () => {
    try { await navigator.clipboard.writeText(SOURCE); copyBtn.textContent = 'Copied'; }
    catch { window.prompt('Copy this link', SOURCE); }
    setTimeout(() => (copyBtn.textContent = 'Copy source link'), 2000);
  });
  fetch(SOURCE).then((r) => r.json()).then((j) => {
    const v = j.apps?.[0]?.versions?.[0];
    if (v?.downloadURL) { const a = $('#ipa'); a.href = v.downloadURL; a.textContent = 'Download IPA ' + v.version; }
  }).catch(() => {});

  const typed = $('.typed');
  const link = 'https://open.spotify.com/track/midnight-drive';

  if (reduce || !window.gsap || !window.ScrollTrigger) {
    $$('.sl').forEach((l, i) => (l.style.opacity = i === 3 ? 1 : 0));
    blocks.forEach((b, i) => { b.classList.add('k'); b.style.color = keyColors[Math.floor(i / 10)]; });
    typed.textContent = link;
    return;
  }

  gsap.registerPlugin(ScrollTrigger);
  const mm = gsap.matchMedia();

  // 1. opening: the headline rises line by line, then the phones fan out
  gsap.timeline({ defaults: { ease: 'power4.out' } })
    .from('.headline .line > span', { yPercent: 110, duration: 1.1, stagger: 0.12 })
    .from('.reveal', { y: 24, opacity: 0, duration: 0.9, stagger: 0.08 }, '-=0.7')
    .from('.fan .main', { y: 160, opacity: 0, duration: 1.2 }, '-=0.8');

  mm.add({ wide: '(min-width: 641px)', narrow: '(max-width: 640px)' }, (ctx) => {
    const spread = ctx.conditions.wide ? 330 : 150;
    gsap.timeline({
      scrollTrigger: { trigger: '.hero', start: 'top top', end: '+=70%', scrub: 0.6 },
    })
      .to('.fan .left', { xPercent: -50, x: -spread, rotate: -8, y: 40, ease: 'none' }, 0)
      .to('.fan .right', { xPercent: -50, x: spread, rotate: 8, y: 40, ease: 'none' }, 0)
      .to('.fan .main', { scale: 0.92, ease: 'none' }, 0)
      .to('.hero-copy', { opacity: 0.15, y: -60, ease: 'none' }, 0);
  });

  // 2. strict encryption: scroll turns the lock into a shield
  const shield = 'M100,30 C112,34 124,38 136,42 C144,45 152,48 160,52 C160,68 160,84 160,100 C160,120 150,138 136,150 C124,160 112,170 100,176 C88,170 76,160 64,150 C50,138 40,120 40,100 C40,84 40,68 40,52 C48,48 56,45 64,42 C76,38 88,34 100,30 Z';
  gsap.set('.ls-shackle', { strokeDasharray: 1, strokeDashoffset: 0 });
  const lines = $$('.sl');
  const st = gsap.timeline({
    scrollTrigger: { trigger: '.strict', start: 'top top', end: 'bottom bottom', scrub: 0.8 },
    defaults: { ease: 'power2.inOut' },
  });
  st.to(lines[0], { opacity: 0, y: -20, duration: 0.3 }, 0.7)
    .fromTo(lines[1], { opacity: 0, y: 20 }, { opacity: 1, y: 0, duration: 0.3 }, 0.9)
    // the shackle lifts and pulls into the body
    .to('.ls-shackle', { y: -18, duration: 0.6 }, 1.2)
    .to(lines[1], { opacity: 0, y: -20, duration: 0.3 }, 1.7)
    .fromTo(lines[2], { opacity: 0, y: 20 }, { opacity: 1, y: 0, duration: 0.3 }, 1.9)
    .to('.ls-shackle', { strokeDashoffset: 1, y: -40, opacity: 0, duration: 0.7 }, 1.9)
    .to('.ls-body, .ls-green', { attr: { d: shield }, duration: 0.9 }, 2.0)
    .to('.ls-green', { opacity: 1, duration: 0.7 }, 2.15)
    .to('.ls-hole', { scale: 0, transformOrigin: '50% 50%', duration: 0.4 }, 2.0)
    .to('.ls-shine', { opacity: 0.16, duration: 0.5 }, 2.6)
    .to('.ls-glow', { opacity: 1, duration: 0.6 }, 2.6)
    .to('.lockshield', { scale: 1.04, duration: 0.6, transformOrigin: '50% 50%' }, 2.6)
    .to(lines[2], { opacity: 0, y: -20, duration: 0.3 }, 3.2)
    .fromTo(lines[3], { opacity: 0, y: 20 }, { opacity: 1, y: 0, duration: 0.3 }, 3.4)
    .to({}, { duration: 0.4 });
  // fill the key blocks as you scroll, a new colour every 10 messages
  ScrollTrigger.create({
    trigger: '.strict', start: 'top top', end: 'bottom bottom',
    onUpdate: (s) => {
      const n = Math.round(s.progress * 30);
      blocks.forEach((b, i) => {
        const on = i < n;
        b.classList.toggle('k', on);
        b.style.color = on ? keyColors[Math.floor(i / 10)] : '';
      });
    },
  });

  // 3. tour: pinned, slides glide sideways
  mm.add('(min-width: 641px)', () => {
    const tr = $('.tour-track');
    const dist = () => Math.max(0, tr.scrollWidth - window.innerWidth);
    gsap.to(tr, {
      x: () => -dist(),
      ease: 'none',
      scrollTrigger: { trigger: '.tour', start: 'top top', end: () => '+=' + dist(), pin: true, scrub: 0.6, invalidateOnRefresh: true },
    });
  });

  // 4. music: the link types, then becomes a card, then the status lights up
  gsap.set('.mcard', { opacity: 0, scale: 0.9, y: 20 });
  gsap.set('.status-pill', { opacity: 0, x: -20 });
  ScrollTrigger.create({
    trigger: '.music', start: 'top 65%', once: true,
    onEnter: () => {
      const tl = gsap.timeline();
      const o = { n: 0 };
      tl.to(o, { n: link.length, duration: 1.1, ease: 'none', onUpdate: () => (typed.textContent = link.slice(0, Math.round(o.n))) })
        .to('.link-typed', { opacity: 0, height: 0, duration: 0.4, ease: 'power2.in' }, '+=0.35')
        .to('.mcard', { opacity: 1, scale: 1, y: 0, duration: 0.8, ease: 'back.out(1.6)' }, '-=0.1')
        .to('.status-pill', { opacity: 1, x: 0, duration: 0.6, ease: 'power3.out' }, '-=0.2');
    },
  });

  // 5. hot words: letters bounce and "HA"s burst out
  const burst = $('.burst');
  ScrollTrigger.create({
    trigger: '.hot', start: 'top 60%', once: true,
    onEnter: () => {
      gsap.from('.hot-word span', { yPercent: 80, rotate: () => gsap.utils.random(-25, 25), opacity: 0, duration: 0.9, stagger: 0.06, ease: 'back.out(2.2)' });
      gsap.to('.hot-word', { rotate: 2, duration: 0.09, repeat: 9, yoyo: true, delay: 0.7, ease: 'none' });
      for (let i = 0; i < 18; i++) {
        const el = document.createElement('i');
        el.textContent = 'HA';
        el.style.left = '50%';
        el.style.top = '45%';
        el.style.fontSize = gsap.utils.random(20, 56) + 'px';
        burst.appendChild(el);
        gsap.fromTo(el, { x: 0, y: 0, scale: 0, opacity: 1 }, {
          x: gsap.utils.random(-600, 600), y: gsap.utils.random(-260, 260), scale: 1, rotate: gsap.utils.random(-40, 40),
          opacity: 0, duration: gsap.utils.random(1.2, 2), delay: 0.6 + i * 0.03, ease: 'power3.out',
          onComplete: () => el.remove(),
        });
      }
    },
  });

  // gentle rise for big headings and blocks further down
  $$('.privacy h2, .facts li, .download h2, .plat, .support, .tour-head h2, .music-copy').forEach((el) => {
    gsap.from(el, { y: 50, opacity: 0, duration: 1, ease: 'power3.out', scrollTrigger: { trigger: el, start: 'top 85%', once: true } });
  });
})();
