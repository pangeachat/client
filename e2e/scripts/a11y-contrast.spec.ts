import fs from "fs";
import path from "path";
import { expect, test } from "../fixtures";

/**
 * Tier-B contrast triage report (NON-GATING): WCAG 1.4.3 / 1.4.11 candidates.
 *
 * axe cannot evaluate contrast here because the pixels live inside an opaque
 * <canvas>; the semantics overlay it audits is transparent. This spec reaches a
 * surface, enumerates labeled leaf nodes in <flt-semantics-host>, screenshots
 * once, and Otsu-splits each node's pixels into fg/bg to estimate the WCAG
 * ratio. Solid-background, sub-threshold nodes are written to
 * test-results/contrast-candidates.json as review candidates.
 *
 * It does NOT fail the build, by design. Empirically (see the probe history),
 * screenshot sampling on this canvas cannot reliably tell text from non-text
 * glyphs, so a low ratio is a CANDIDATE, not a verdict — an agent/human
 * confirms whether the sampled foreground is really text and really failing.
 * That is why contrast is Tier-B (triage), not a Tier-A gate. See
 * accessibility.instructions.md.
 */

async function gotoSurface(
  page: import("@playwright/test").Page,
  hash: string,
  sentinel: import("@playwright/test").Locator,
) {
  await page.goto(hash);
  await page.mouse.move(640, 400);
  await page.mouse.wheel(0, -500);
  await expect(sentinel).toBeVisible({ timeout: 90_000 });
}

type Sample = {
  label: string;
  role: string;
  rect: { x: number; y: number; w: number; h: number };
  bg: [number, number, number];
  fg: [number, number, number];
  ratio: number;
  solidity: number; // fraction of pixels near the background luminance
  sampled: number;
};

/**
 * Sample every labeled leaf node's contrast from a single screenshot.
 * Runs in the browser: decodes the PNG once, then for each semantics node
 * histograms its pixel region into a dominant background cluster and the
 * highest-luminance-distance foreground cluster, and computes the WCAG ratio.
 */
async function sampleContrast(
  page: import("@playwright/test").Page,
): Promise<Sample[]> {
  const b64 = (await page.screenshot()).toString("base64");
  return page.evaluate(async (pngB64: string) => {
    const img = new Image();
    img.src = "data:image/png;base64," + pngB64;
    await img.decode();
    const cv = document.createElement("canvas");
    cv.width = img.naturalWidth;
    cv.height = img.naturalHeight;
    const ctx = cv.getContext("2d")!;
    ctx.drawImage(img, 0, 0);
    const { data, width, height } = ctx.getImageData(0, 0, cv.width, cv.height);
    const dpr = img.naturalWidth / window.innerWidth;

    const srgb = (c: number) => {
      const x = c / 255;
      return x <= 0.03928 ? x / 12.92 : Math.pow((x + 0.055) / 1.055, 2.4);
    };
    const lum = (r: number, g: number, b: number) =>
      0.2126 * srgb(r) + 0.7152 * srgb(g) + 0.0722 * srgb(b);
    const ratio = (a: number[], b: number[]) => {
      const l1 = lum(a[0], a[1], a[2]);
      const l2 = lum(b[0], b[1], b[2]);
      const hi = Math.max(l1, l2);
      const lo = Math.min(l1, l2);
      return (hi + 0.05) / (lo + 0.05);
    };

    // Otsu bimodal split: separate a region into a darker and lighter class by
    // the luma threshold that maximizes between-class variance, then take each
    // class's mean RGB. This isolates text from background without a fixed mass
    // floor (text is a small but high-contrast minority).
    function sampleRegion(x: number, y: number, w: number, h: number) {
      const px0 = Math.max(0, Math.round(x * dpr));
      const py0 = Math.max(0, Math.round(y * dpr));
      const px1 = Math.min(width, Math.round((x + w) * dpr));
      const py1 = Math.min(height, Math.round((y + h) * dpr));
      const luma = (r: number, g: number, b: number) =>
        Math.round(0.299 * r + 0.587 * g + 0.114 * b);
      // Per-luma-bin pixel count + summed rgb.
      const cnt = new Array(256).fill(0);
      const sr = new Array(256).fill(0);
      const sg = new Array(256).fill(0);
      const sb = new Array(256).fill(0);
      let total = 0;
      for (let py = py0; py < py1; py++) {
        for (let px = px0; px < px1; px++) {
          const i = (py * width + px) * 4;
          const r = data[i];
          const g = data[i + 1];
          const b = data[i + 2];
          const y8 = luma(r, g, b);
          cnt[y8]++;
          sr[y8] += r;
          sg[y8] += g;
          sb[y8] += b;
          total++;
        }
      }
      if (total < 25) return null;
      // Otsu threshold over the luma histogram.
      let sumAll = 0;
      for (let t = 0; t < 256; t++) sumAll += t * cnt[t];
      let wB = 0;
      let sumB = 0;
      let best = -1;
      let thr = 127;
      for (let t = 0; t < 256; t++) {
        wB += cnt[t];
        if (wB === 0) continue;
        const wF = total - wB;
        if (wF === 0) break;
        sumB += t * cnt[t];
        const mB = sumB / wB;
        const mF = (sumAll - sumB) / wF;
        const between = wB * wF * (mB - mF) * (mB - mF);
        if (between > best) {
          best = between;
          thr = t;
        }
      }
      const cls = (lo: number, hi: number) => {
        let n = 0;
        let R = 0;
        let G = 0;
        let B = 0;
        for (let t = lo; t <= hi; t++) {
          n += cnt[t];
          R += sr[t];
          G += sg[t];
          B += sb[t];
        }
        return n ? { n, rgb: [R / n, G / n, B / n] } : null;
      };
      const dark = cls(0, thr);
      const light = cls(thr + 1, 255);
      if (!dark || !light) return null; // single-luma region (e.g. blank)
      const bgCls = dark.n >= light.n ? dark : light; // background = majority
      const fgCls = dark.n >= light.n ? light : dark;
      // Solidity: share of pixels within ±10 luma of the background class mean.
      const bgLuma = luma(bgCls.rgb[0], bgCls.rgb[1], bgCls.rgb[2]);
      let near = 0;
      for (let t = 0; t < 256; t++) if (Math.abs(t - bgLuma) <= 10) near += cnt[t];
      return {
        bg: bgCls.rgb.map(Math.round) as [number, number, number],
        fg: fgCls.rgb.map(Math.round) as [number, number, number],
        ratio: Math.round(ratio(bgCls.rgb, fgCls.rgb) * 100) / 100,
        solidity: Math.round((near / total) * 100) / 100,
        sampled: total,
      };
    }

    const host = document.querySelector("flt-semantics-host");
    if (!host) return [];
    const out: any[] = [];
    const nodes = host.querySelectorAll("[aria-label]");
    for (const el of Array.from(nodes)) {
      // Leaf only: no labeled descendant (avoid container rects).
      if (el.querySelector("[aria-label]")) continue;
      const label = (el.getAttribute("aria-label") || "").trim();
      if (!label) continue;
      const r = el.getBoundingClientRect();
      if (r.width < 4 || r.height < 4) continue;
      if (r.width > 320 || r.height > 140) continue; // control/text sized
      if (r.x < 0 || r.y < 0 || r.right > window.innerWidth || r.bottom > window.innerHeight)
        continue; // fully in viewport for clean sampling
      const s = sampleRegion(r.x, r.y, r.width, r.height);
      if (!s) continue;
      out.push({
        label: label.slice(0, 40),
        role: el.getAttribute("role") || el.tagName.toLowerCase(),
        rect: {
          x: Math.round(r.x),
          y: Math.round(r.y),
          w: Math.round(r.width),
          h: Math.round(r.height),
        },
        ...s,
      });
    }
    return out.sort((a, b) => a.ratio - b.ratio);
  }, b64);
}

function report(surface: string, samples: Sample[]) {
  const lines = samples.map(
    (s) =>
      `  ${s.ratio.toFixed(2).padStart(6)}:1  sol=${s.solidity
        .toFixed(2)
        .padStart(4)}  [${s.role}] ${JSON.stringify(s.bg)}/${JSON.stringify(
        s.fg,
      )}  "${s.label}"`,
  );
  // eslint-disable-next-line no-console
  console.log(
    `\n=== contrast probe: ${surface} (${samples.length} labeled leaf nodes) ===\n` +
      lines.join("\n"),
  );
}

test.describe("Contrast triage report (non-gating)", () => {
  test.use({ storageState: path.join(__dirname, "..", ".auth", "user.json") });
  test.setTimeout(120_000);

  const intl = JSON.parse(
    fs.readFileSync(path.resolve(__dirname, "../../lib/l10n/intl_en.arb"), "utf-8"),
  );

  test("sample contrast and emit triage candidates", async ({ page }) => {
    const surfaces: { name: string; hash: string; sentinel: import("@playwright/test").Locator }[] = [
      { name: "world map", hash: "/#/", sentinel: page.getByRole("textbox", { name: intl.mapSearchHint }) },
      { name: "chat list", hash: "/#/?left=chats", sentinel: page.getByRole("button", { name: intl.chatWithSupport }).first() },
      { name: "settings", hash: "/#/?right=settings", sentinel: page.getByRole("button", { name: intl.learningSettings }).first() },
    ];

    const candidates: (Sample & { surface: string; confidence: string })[] = [];
    for (const s of surfaces) {
      await gotoSurface(page, s.hash, s.sentinel);
      const samples = await sampleContrast(page);
      report(s.name, samples);
      for (const sm of samples) {
        // Solid-background, sub-threshold nodes are candidates for review.
        // confidence reflects only sampling certainty, never a verdict — a low
        // ratio may be a real failure OR a non-text glyph the sampler mistook
        // for text. A human/agent confirms (see accessibility.instructions.md).
        if (sm.ratio < 4.5 && sm.solidity >= 0.7) {
          candidates.push({
            surface: s.name,
            confidence: sm.solidity >= 0.85 && sm.ratio < 3.0 ? "high" : "review",
            ...sm,
          });
        }
      }
    }

    const outDir = path.resolve(__dirname, "../../test-results");
    fs.mkdirSync(outDir, { recursive: true });
    fs.writeFileSync(
      path.join(outDir, "contrast-candidates.json"),
      JSON.stringify({ generatedFrom: process.env.BASE_URL, candidates }, null, 2),
    );
    // eslint-disable-next-line no-console
    console.log(
      `\n=== contrast triage: ${candidates.length} candidate(s) for manual/agent review ` +
        `(${candidates.filter((c) => c.confidence === "high").length} higher-confidence) ` +
        `-> test-results/contrast-candidates.json ===`,
    );
    // Non-gating: this is Tier-B evidence, not a pass/fail criterion.
    expect(Array.isArray(candidates)).toBe(true);
  });
});
