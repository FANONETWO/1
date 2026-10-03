// tools/leonardo-bot/bot.mjs
// Leonardo 网页自动化：复用本机 Chrome（真实浏览器内核 + 持久化登录态）。
//
// 用法（在本目录下执行）：
//   node bot.mjs probe                       # 打开 Leonardo 截图 + dump DOM（调试选择器）
//   node bot.mjs login                       # 被动检测登录态（已登录则秒退）
//   node bot.mjs gen --batch batch1.json --out assets/raw/batch1
//
// 关键设计（都是踩过坑后的结论）：
// - launchPersistentContext + channel:'chrome'：复用系统已装 Chrome，无需下载 Chromium
// - headless:false：Leonardo 有 Cloudflare 防护，无头浏览器会被拦（实测 headed 正常）
// - 登录页与生成页的输入框 id 不同：落地页 #home-prompt-textarea，生成页 #prompt-textarea
// - 页面绝不做循环导航/刷新（只按宽高比切换时导航一次）
// - 结果识别用「图片 URL 集合差集」，避免把历史生成图当成新结果
// - 取图必须在页面内 fetch：Node 直连 cdn.leonardo.ai 会 ETIMEDOUT，浏览器内正常
// - 登录态保存在 <项目根>/.secrets/chrome-profile（已 gitignore），不接触账号密码

import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright-core';

const HERE = import.meta.dirname;
const ROOT = path.resolve(HERE, '..', '..');
const PROFILE = path.join(ROOT, '.secrets', 'chrome-profile');
const SHOT_DIR = path.join(ROOT, 'assets', 'raw', '_probe');

// 用户指定的像素风格预设
const STYLE_ID = '111dc692-d470-4eec-b791-3475abac4c46';
const BASE_GEN = 'https://app.leonardo.ai/generate';
const COMMON_Q = `model=auto-preset&style=${STYLE_ID}&mode=fast&interpolation=false&quantity=1&seedEnabled=false&negativePromptEnabled=false&promptEnhance=AUTO`;

const log = (...a) => console.log('[bot]', ...a);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function arg(name, def = null) {
  const i = process.argv.indexOf('--' + name);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : def;
}

function genUrl(aspect = '1:1') {
  return `${BASE_GEN}?${COMMON_Q}&aspectRatio=${encodeURIComponent(aspect)}`;
}

async function openBrowser(headless = false) {
  fs.mkdirSync(PROFILE, { recursive: true });
  return chromium.launchPersistentContext(PROFILE, {
    channel: 'chrome',
    headless,
    viewport: { width: 1440, height: 980 },
    locale: 'zh-CN',
    acceptDownloads: true,
    args: ['--disable-blink-features=AutomationControlled'],
  });
}

// ——— probe：验证可达性 + 采集页面结构 ———
async function probe() {
  fs.mkdirSync(SHOT_DIR, { recursive: true });
  const ctx = await openBrowser(false);
  const page = ctx.pages()[0] ?? (await ctx.newPage());
  let status = 'no-response';
  try {
    const resp = await page.goto(genUrl('1:1'), { waitUntil: 'domcontentloaded', timeout: 60000 });
    status = resp ? String(resp.status()) : 'null-resp';
  } catch (e) {
    log('goto error:', e.message);
  }
  await sleep(9000);
  const shot = path.join(SHOT_DIR, 'leonardo_probe.png');
  await page.screenshot({ path: shot });
  log('status =', status);
  log('url    =', page.url());
  log('生成页输入框 #prompt-textarea =', (await page.locator('#prompt-textarea').count()) > 0);
  log('落地页输入框 #home-prompt-textarea =', (await page.locator('#home-prompt-textarea').count()) > 0);
  log('shot   =', shot);

  const info = await page.evaluate(() => {
    const pick = (sel) =>
      Array.from(document.querySelectorAll(sel))
        .slice(0, 15)
        .map((e) => ({
          tag: e.tagName.toLowerCase(),
          placeholder: e.placeholder || e.getAttribute('aria-label') || '',
          id: e.id || '',
          text: (e.innerText || '').trim().slice(0, 40),
        }));
    return {
      textareas: pick('textarea'),
      buttons: pick('button'),
      resultImgs: Array.from(document.querySelectorAll('img'))
        .map((i) => i.src)
        .filter((s) => s && s.includes('cdn.leonardo.ai/users/'))
        .slice(0, 5),
      bodyHead: (document.body.innerText || '').replace(/\n{2,}/g, '\n').slice(0, 900),
    };
  });
  fs.writeFileSync(path.join(SHOT_DIR, 'leonardo_dom.json'), JSON.stringify(info, null, 2), 'utf8');
  log('dom    =', path.join(SHOT_DIR, 'leonardo_dom.json'));
  await ctx.close();
}

// ——— login：被动检测登录态（只读 cookie 与页面结构，不刷新、不碰输入框）———
async function login() {
  const ctx = await openBrowser(false);
  const page = ctx.pages()[0] ?? (await ctx.newPage());
  await page.goto(genUrl('1:1'), { waitUntil: 'domcontentloaded', timeout: 60000 }).catch(() => {});
  await sleep(6000);

  const probeState = async () => {
    const cookies = await ctx.cookies('https://app.leonardo.ai').catch(() => []);
    const hasSession = cookies.some(
      (c) => /next-auth|session|token|auth/i.test(c.name) && c.value && c.value.length > 12
    );
    const hasBox = (await page.locator('#prompt-textarea').count()) > 0;
    return { hasSession, hasBox, names: cookies.map((c) => c.name) };
  };

  fs.mkdirSync(SHOT_DIR, { recursive: true });
  let st = await probeState();
  if (st.hasSession && st.hasBox) {
    await page.screenshot({ path: path.join(SHOT_DIR, 'leonardo_login_ok.png') });
    log('已检测到登录态，无需再次登录。');
    await ctx.close();
    process.exit(0);
  }

  log('尚未检测到登录态。请在打开的窗口里登录（Google / 邮箱均可），无需关闭窗口。');
  log('每 8 秒被动检测一次，最多等 12 分钟……');
  const deadline = Date.now() + 12 * 60 * 1000;
  let ok = false;
  while (Date.now() < deadline) {
    await sleep(8000);
    st = await probeState();
    if (st.hasSession && st.hasBox) {
      ok = true;
      break;
    }
  }
  await page.screenshot({ path: path.join(SHOT_DIR, ok ? 'leonardo_login_ok.png' : 'leonardo_login_fail.png') });
  log(ok ? '登录成功，登录态已保存到本地 profile。' : '超时未检测到登录。cookie：' + st.names.slice(0, 10).join(', '));
  await ctx.close();
  process.exit(ok ? 0 : 1);
}

// ——— 生成相关工具 ———

// 只采集真正的生成结果图（cdn.leonardo.ai/users/...），排除头像/logo/历史封面
async function resultImageUrls(page) {
  return page.evaluate(() =>
    Array.from(document.querySelectorAll('img'))
      .map((i) => i.src)
      .filter((s) => s && s.includes('cdn.leonardo.ai/users/'))
  );
}

// 提交生成：多种选择器策略 + 键盘回退（页面结构随版本可能变化）
async function submitGeneration(page) {
  const strategies = [
    { name: 'role=button[Generate]', loc: () => page.getByRole('button', { name: 'Generate', exact: true }) },
    { name: 'button:has-text(Generate)', loc: () => page.locator('button:has-text("Generate")') },
    { name: 'role=button:has-text(Generate)', loc: () => page.locator('[role="button"]:has-text("Generate")') },
  ];
  for (const s of strategies) {
    try {
      const loc = s.loc();
      const n = await loc.count();
      for (let i = n - 1; i >= 0; i--) {
        const el = loc.nth(i);
        const vis = await el.isVisible().catch(() => false);
        const en = vis ? await el.isEnabled().catch(() => false) : false;
        if (vis && en) {
          await el.click({ timeout: 8000 });
          log('  提交方式：' + s.name);
          return true;
        }
      }
    } catch {
      /* 尝试下一个策略 */
    }
  }
  try {
    await page.locator('#prompt-textarea').click();
    await page.keyboard.press('Control+Enter');
    log('  提交方式：Ctrl+Enter 回退');
    return true;
  } catch {
    return false;
  }
}

// 等待新结果图：用提交前的 URL 集合做差集，避免把历史生成图当新结果
async function waitForNewImages(page, beforeSet, want, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const urls = await resultImageUrls(page);
    const fresh = urls.filter((u) => !beforeSet.has(u));
    if (fresh.length >= want) return fresh;
    const blocked = await page.evaluate(() => {
      const t = (document.body.innerText || '').toLowerCase();
      return t.includes('out of tokens') || t.includes('insufficient tokens');
    });
    if (blocked) throw new Error('额度不足（页面提示 out of tokens）');
    await sleep(4000);
  }
  throw new Error(`等待生成超时（${timeoutMs / 1000}s）`);
}

// 在页面上下文里取图：Node 直连 cdn.leonardo.ai 会超时，浏览器内 fetch 正常
async function downloadViaPage(page, url, file) {
  const res = await page.evaluate(async (u) => {
    try {
      const r = await fetch(u);
      if (!r.ok) return { ok: false, info: 'HTTP ' + r.status };
      const buf = await r.arrayBuffer();
      const bytes = new Uint8Array(buf);
      let bin = '';
      const CH = 0x8000;
      for (let i = 0; i < bytes.length; i += CH) {
        bin += String.fromCharCode.apply(null, bytes.subarray(i, i + CH));
      }
      return { ok: true, b64: btoa(bin) };
    } catch (e) {
      return { ok: false, info: String(e) };
    }
  }, url);
  if (!res.ok) throw new Error(`页面内取图失败：${res.info}`);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, Buffer.from(res.b64, 'base64'));
  return fs.statSync(file).size;
}

// ——— gen：批量生成 ———
async function gen() {
  const batchFile = arg('batch');
  if (!batchFile) {
    log('缺少 --batch <file.json>');
    process.exit(1);
  }
  const outDir = path.resolve(ROOT, arg('out', 'assets/raw/batch'));
  // 容忍 Windows 上可能出现的 UTF-8 BOM
  const rawBatch = fs.readFileSync(path.resolve(HERE, batchFile), 'utf8').replace(/^\uFEFF/, '');
  const items = JSON.parse(rawBatch);
  // 按宽高比分组，减少页面切换（每次切换都会导航一次）
  items.sort((a, b) => String(a.aspect || '1:1').localeCompare(String(b.aspect || '1:1')));
  fs.mkdirSync(outDir, { recursive: true });
  log(`批次 ${batchFile}：${items.length} 项 → ${outDir}`);

  const ctx = await openBrowser(false);
  const page = ctx.pages()[0] ?? (await ctx.newPage());
  let currentAspect = '';
  const manifest = [];

  for (const it of items) {
    const aspect = it.aspect || '1:1';
    if (aspect !== currentAspect) {
      await page.goto(genUrl(aspect), { waitUntil: 'domcontentloaded', timeout: 60000 });
      await page.waitForSelector('#prompt-textarea', { timeout: 60000 });
      await sleep(4000);
      currentAspect = aspect;
    }
    const want = it.count || 1;
    log(`▶ ${it.id}（${aspect} × ${want}）`);
    await page.fill('#prompt-textarea', it.prompt);
    await sleep(700);
    const beforeSet = new Set(await resultImageUrls(page));
    await submitGeneration(page);

    let fresh = [];
    try {
      fresh = await waitForNewImages(page, beforeSet, want, 300000);
    } catch (e) {
      log(`✗ ${it.id}：${e.message}`);
      await page.screenshot({ path: path.join(SHOT_DIR, `leonardo_${it.id}_fail.png`) });
      manifest.push({ id: it.id, ok: false, error: e.message });
      continue;
    }

    for (let i = 0; i < fresh.length; i++) {
      const file = path.join(outDir, `${it.id}_${i + 1}.jpg`);
      try {
        const size = await downloadViaPage(page, fresh[i], file);
        log(`  ✔ ${path.basename(file)} (${size} B)`);
        manifest.push({ id: it.id, ok: true, file, url: fresh[i], prompt: it.prompt, aspect });
      } catch (e) {
        log(`  ✗ 下载失败：${e.message}`);
        manifest.push({ id: it.id, ok: false, error: e.message, url: fresh[i] });
      }
    }
    await sleep(3000);
  }

  const mf = path.join(outDir, 'manifest.json');
  fs.writeFileSync(mf, JSON.stringify(manifest, null, 2), 'utf8');
  log('清单 =', mf);
  const okCount = manifest.filter((m) => m.ok).length;
  log(`完成：成功 ${okCount} / ${manifest.length}`);
  await ctx.close();
  process.exit(okCount > 0 ? 0 : 1);
}

const cmd = process.argv[2] || 'probe';
if (cmd === 'probe') await probe();
else if (cmd === 'login') await login();
else if (cmd === 'gen') await gen();
else {
  log('未知命令：', cmd, '（可用：probe / login / gen）');
  process.exit(1);
}
