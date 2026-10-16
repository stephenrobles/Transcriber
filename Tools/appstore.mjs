#!/usr/bin/env node
// Fills in the App Store Connect listing for Transcriber from AppStore/metadata.md, uploads screenshots,
// attaches the latest processed builds and submits for review.
//
// Usage: node Tools/appstore.mjs <command> [--platform ios|mac|all]
//   metadata     name/subtitle/privacy URL, categories, version text (description, keywords, …)
//   screenshots  replace the screenshot sets with AppStore/screenshots/{mac,iphone,ipad}-*.png
//   attach       attach the newest processed build (1.2 / 8) to each platform's 1.2 version
//   submit       submit both platform versions for review
//   status       print versions, builds and review state
// Auth: App Store Connect API key at ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8.
import { createPrivateKey, sign, createHash } from "node:crypto";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const KEY_ID = process.env.ASC_KEY_ID || "Z5YD293RLM";
const ISSUER_ID = process.env.ASC_ISSUER_ID || "69a6de84-dcf8-47e3-e053-5b8c7c11a4d1";
const BUNDLE_ID = "fm.beard.Transcriber";
const VERSION = "1.2";
const BUILD = "10";
const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const API = "https://api.appstoreconnect.apple.com/v1";

// ---------- auth ----------
const b64url = (b) => Buffer.from(b).toString("base64").replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
function token() {
  const key = createPrivateKey(readFileSync(join(homedir(), ".appstoreconnect/private_keys", `AuthKey_${KEY_ID}.p8`)));
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "ES256", kid: KEY_ID, typ: "JWT" }));
  const payload = b64url(JSON.stringify({ iss: ISSUER_ID, iat: now, exp: now + 1100, aud: "appstoreconnect-v1" }));
  const sig = sign("sha256", Buffer.from(`${header}.${payload}`), { key, dsaEncoding: "ieee-p1363" });
  return `${header}.${payload}.${b64url(sig)}`;
}
async function api(method, path, body, raw) {
  const res = await fetch(path.startsWith("http") ? path : API + path, {
    method,
    headers: { Authorization: `Bearer ${token()}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (res.status === 204) return null;
  const text = await res.text();
  let json; try { json = JSON.parse(text); } catch { json = text; }
  if (!res.ok) throw new Error(`${method} ${path} → ${res.status}: ${typeof json === "string" ? json : JSON.stringify(json.errors ?? json)}`);
  return raw ? json : json;
}
const get = (p) => api("GET", p), post = (p, b) => api("POST", p, b), patch = (p, b) => api("PATCH", p, b), del = (p) => api("DELETE", p);
async function all(path) {
  let out = [], next = path;
  while (next) { const page = await get(next); out = out.concat(page.data); next = page.links?.next; }
  return out;
}

// ---------- metadata.md ----------
const md = readFileSync(join(ROOT, "AppStore/metadata.md"), "utf8");
const field = (label) => { const m = md.match(new RegExp(`\\*\\*${label}[^*]*\\*\\*\\s*(.+)`)); return m ? m[1].trim() : null; };
const block = (label) => { const m = md.match(new RegExp(`\\*\\*${label}[^*]*\\*\\*\\n([\\s\\S]*?)\\n\\n\\*\\*`)); return m ? m[1].trim() : null; };
const META = {
  subtitle: field("Subtitle \\(30\\):"),
  privacyPolicyUrl: field("Privacy policy URL:"),
  supportUrl: field("Support URL:"),
  marketingUrl: field("Marketing URL:"),
  copyright: field("Copyright:"),
  promotionalText: block("Promotional text"),
  description: block("Description"),
  keywords: block("Keywords"),
  whatsNew: block("What's New"),
  reviewNotes: (md.match(/- \*\*Notes:\*\*\n([\s\S]*?)\n\n## /) || [])[1]?.replace(/\n  /g, " ").trim(),
};

// ---------- lookups ----------
async function app() {
  const apps = await get(`/apps?filter[bundleId]=${BUNDLE_ID}`);
  if (!apps.data.length) throw new Error(`No app with bundle id ${BUNDLE_ID}`);
  return apps.data[0];
}
const PLATFORMS = { ios: "IOS", mac: "MAC_OS" };
function wanted() {
  const i = process.argv.indexOf("--platform");
  const p = i > 0 ? process.argv[i + 1] : "all";
  return p === "all" ? Object.values(PLATFORMS) : [PLATFORMS[p]];
}
async function version(appId, platform) {
  const versions = await get(`/apps/${appId}/appStoreVersions?filter[platform]=${platform}&limit=5`);
  let v = versions.data.find((x) => x.attributes.versionString === VERSION) ?? versions.data.find((x) => !["READY_FOR_SALE", "REPLACED_WITH_NEW_VERSION"].includes(x.attributes.appStoreState));
  if (!v) {
    v = (await post("/appStoreVersions", { data: { type: "appStoreVersions", attributes: { platform, versionString: VERSION, copyright: META.copyright }, relationships: { app: { data: { type: "apps", id: appId } } } } })).data;
    console.log(`created ${platform} version ${VERSION}`);
  }
  return v;
}

/// The review contact phone already on file for one of Stephen's other apps.
async function reviewPhoneFromOtherApp() {
  for (const bundle of ["fm.beard.Leveler", "fm.beard.Captioner", "fm.beard.KanDo"]) {
    const apps = await get(`/apps?filter[bundleId]=${bundle}`).catch(() => null);
    for (const other of apps?.data ?? []) {
      const versions = await get(`/apps/${other.id}/appStoreVersions?limit=3`).catch(() => null);
      for (const v of versions?.data ?? []) {
        const d = await get(`/appStoreVersions/${v.id}/appStoreReviewDetail`).catch(() => null);
        if (d?.data?.attributes?.contactPhone) return d.data.attributes.contactPhone;
      }
    }
  }
  return null;
}

// ---------- commands ----------
async function metadata() {
  const a = await app();
  const infos = await get(`/apps/${a.id}/appInfos`);
  const info = infos.data.find((x) => x.attributes.appStoreState !== "READY_FOR_SALE") ?? infos.data[0];
  const locs = await get(`/appInfos/${info.id}/appInfoLocalizations`);
  for (const loc of locs.data.filter((l) => l.attributes.locale === "en-US")) {
    await patch(`/appInfoLocalizations/${loc.id}`, { data: { type: "appInfoLocalizations", id: loc.id, attributes: { subtitle: META.subtitle, privacyPolicyUrl: META.privacyPolicyUrl } } });
    console.log("app info localization updated:", loc.attributes.name);
  }
  const cats = await get(`/appCategories?filter[platforms]=IOS,MAC_OS&limit=200`);
  const cat = (id) => cats.data.find((c) => c.id === id) ? { type: "appCategories", id } : null;
  await patch(`/appInfos/${info.id}`, { data: { type: "appInfos", id: info.id, relationships: {
    primaryCategory: { data: cat("PRODUCTIVITY") }, secondaryCategory: { data: cat("PHOTO_AND_VIDEO") } } } });
  console.log("categories set");
  for (const platform of wanted()) {
    const v = await version(a.id, platform);
    await patch(`/appStoreVersions/${v.id}`, { data: { type: "appStoreVersions", id: v.id, attributes: { copyright: META.copyright, versionString: VERSION } } });
    const vlocs = await get(`/appStoreVersions/${v.id}/appStoreVersionLocalizations`);
    let loc = vlocs.data.find((l) => l.attributes.locale === "en-US");
    const attrs = { description: META.description, keywords: META.keywords, promotionalText: META.promotionalText, supportUrl: META.supportUrl, marketingUrl: META.marketingUrl, whatsNew: META.whatsNew };
    // A first release has no "What's New"; App Store Connect rejects the field, so drop it on that error.
    const save = async (a) => {
      if (!loc) loc = (await post("/appStoreVersionLocalizations", { data: { type: "appStoreVersionLocalizations", attributes: { locale: "en-US", ...a }, relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: v.id } } } } })).data;
      else await patch(`/appStoreVersionLocalizations/${loc.id}`, { data: { type: "appStoreVersionLocalizations", id: loc.id, attributes: a } });
    };
    try { await save(attrs); } catch (e) {
      if (!/whatsNew/.test(e.message)) throw e;
      const { whatsNew, ...rest } = attrs; await save(rest);
    }
    // Review details
    const details = await get(`/appStoreVersions/${v.id}/appStoreReviewDetail`).catch(() => null);
    const review = { contactFirstName: "Stephen", contactLastName: "Robles", contactEmail: "steve@beard.fm", demoAccountRequired: false, notes: META.reviewNotes };
    const phone = process.env.ASC_PHONE || await reviewPhoneFromOtherApp();
    if (phone) review.contactPhone = phone;
    if (details?.data) await patch(`/appStoreReviewDetails/${details.data.id}`, { data: { type: "appStoreReviewDetails", id: details.data.id, attributes: review } });
    else await post("/appStoreReviewDetails", { data: { type: "appStoreReviewDetails", attributes: review, relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: v.id } } } } });
    console.log(`${platform} ${VERSION}: text and review details set`);
  }
}

const DISPLAY_TYPES = { mac: "APP_DESKTOP", iphone: "APP_IPHONE_67", ipad: "APP_IPAD_PRO_3GEN_129" };
async function screenshots() {
  const a = await app();
  for (const platform of wanted()) {
    const v = await version(a.id, platform);
    const vlocs = await get(`/appStoreVersions/${v.id}/appStoreVersionLocalizations`);
    const loc = vlocs.data.find((l) => l.attributes.locale === "en-US");
    const kinds = platform === "MAC_OS" ? ["mac"] : ["iphone", "ipad"];
    for (const kind of kinds) {
      const files = readdirSync(join(ROOT, "AppStore/screenshots")).filter((f) => f.startsWith(kind + "-") && f.endsWith(".png")).sort();
      if (!files.length) continue;
      const sets = await get(`/appStoreVersionLocalizations/${loc.id}/appScreenshotSets`);
      let set = sets.data.find((s) => s.attributes.screenshotDisplayType === DISPLAY_TYPES[kind]);
      if (set) { for (const shot of (await get(`/appScreenshotSets/${set.id}/appScreenshots`)).data) await del(`/appScreenshots/${shot.id}`); }
      else set = (await post("/appScreenshotSets", { data: { type: "appScreenshotSets", attributes: { screenshotDisplayType: DISPLAY_TYPES[kind] }, relationships: { appStoreVersionLocalization: { data: { type: "appStoreVersionLocalizations", id: loc.id } } } } })).data;
      for (const file of files) {
        const data = readFileSync(join(ROOT, "AppStore/screenshots", file));
        const shot = (await post("/appScreenshots", { data: { type: "appScreenshots", attributes: { fileName: file, fileSize: data.length }, relationships: { appScreenshotSet: { data: { type: "appScreenshotSets", id: set.id } } } } })).data;
        for (const op of shot.attributes.uploadOperations) {
          const chunk = data.subarray(op.offset, op.offset + op.length);
          const headers = Object.fromEntries(op.requestHeaders.map((h) => [h.name, h.value]));
          const r = await fetch(op.url, { method: op.method, headers, body: chunk });
          if (!r.ok) throw new Error(`upload chunk failed: ${r.status}`);
        }
        await patch(`/appScreenshots/${shot.id}`, { data: { type: "appScreenshots", id: shot.id, attributes: { uploaded: true, sourceFileChecksum: createHash("md5").update(data).digest("hex") } } });
        console.log(`${platform} ${kind}: uploaded ${file}`);
      }
    }
  }
}

async function attach() {
  const a = await app();
  for (const platform of wanted()) {
    const v = await version(a.id, platform);
    // Newest processed build for this platform (build numbers may differ between platforms).
    const builds = await get(`/builds?filter[app]=${a.id}&filter[preReleaseVersion.platform]=${platform}&sort=-uploadedDate&limit=10`);
    const build = builds.data.find((b) => b.attributes.processingState === "VALID");
    if (!build) { console.log(`${platform}: no processed build yet (${builds.data.map((b) => b.attributes.version + ":" + b.attributes.processingState).join(", ") || "none"})`); continue; }
    await patch(`/appStoreVersions/${v.id}/relationships/build`, { data: { type: "builds", id: build.id } });
    console.log(`${platform}: attached build ${build.attributes.version} (${build.id})`);
  }
}

async function submit() {
  const a = await app();
  for (const platform of wanted()) {
    const v = await version(a.id, platform);
    const sub = (await post("/reviewSubmissions", { data: { type: "reviewSubmissions", attributes: { platform }, relationships: { app: { data: { type: "apps", id: a.id } } } } })).data;
    await post("/reviewSubmissionItems", { data: { type: "reviewSubmissionItems", relationships: { reviewSubmission: { data: { type: "reviewSubmissions", id: sub.id } }, appStoreVersion: { data: { type: "appStoreVersions", id: v.id } } } } });
    await patch(`/reviewSubmissions/${sub.id}`, { data: { type: "reviewSubmissions", id: sub.id, attributes: { submitted: true } } });
    console.log(`${platform}: submitted for review (${sub.id})`);
  }
}

async function status() {
  const a = await app();
  console.log(`${a.attributes.name} (${a.id})`);
  for (const platform of Object.values(PLATFORMS)) {
    const versions = await get(`/apps/${a.id}/appStoreVersions?filter[platform]=${platform}&limit=5`);
    for (const v of versions.data) console.log(`  ${platform} ${v.attributes.versionString}: ${v.attributes.appStoreState}`);
    const builds = await get(`/builds?filter[app]=${a.id}&filter[preReleaseVersion.platform]=${platform}&sort=-uploadedDate&limit=5`);
    for (const b of builds.data) console.log(`    build ${b.attributes.version}: ${b.attributes.processingState}`);
  }
}

const commands = { metadata, screenshots, attach, submit, status };
const cmd = commands[process.argv[2]];
if (!cmd) { console.error("usage: node Tools/appstore.mjs metadata|screenshots|attach|submit|status [--platform ios|mac|all]"); process.exit(1); }
cmd().catch((e) => { console.error(e.message); process.exit(1); });
