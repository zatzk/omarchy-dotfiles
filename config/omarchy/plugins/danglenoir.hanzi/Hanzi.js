#!/usr/bin/env node
/**
 * Fetch and normalize a daily Chinese character from English Wiktionary.
 */

const fs = require("node:fs");
const path = require("node:path");
const https = require("node:https");
const os = require("node:os");
const { parseArgs } = require("node:util");

const API_ORIGIN = "https://en.wiktionary.org";
const API_PATH = "/w/api.php";
const ALLOWED_HOSTS = new Set(["en.wiktionary.org"]);
const USER_AGENT = "Omarchy-Hanzi/1.0 (https://github.com/danglenoir/omarchy-hanzi)";
const HSK_APPENDIX = "Appendix:HSK_list_of_Mandarin_words_v3.0/characters";
const DEFAULT_LEVELS = ["I-1", "I-2", "I-3"];
const MAX_DISPLAY_LENGTH = 200;
const MAX_RESPONSE_BYTES = 3 * 1024 * 1024;
const MAX_COMPONENTS = 6;
const MAX_WORDS = 3;
const MAX_WORD_CANDIDATES = 10;
const MAX_GLOSSES = 3;
function isCjkCodePoint(code) {
  return (code >= 0x3400 && code <= 0x9FFF)
    || (code >= 0xF900 && code <= 0xFAFF)
    || (code >= 0x20000 && code <= 0x323AF);
}

function isIdcCodePoint(code) {
  return code >= 0x2FF0 && code <= 0x2FFB;
}

class WidgetError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
    this.name = "WidgetError";
  }
}

function isAllowedUrl(url) {
  try {
    const parsed = new URL(url);
    return parsed.protocol === "https:" && ALLOWED_HOSTS.has(parsed.hostname);
  } catch (err) {
    return false;
  }
}

function getJson(url, timeoutMs = 20000) {
  return new Promise((resolve, reject) => {
    if (!isAllowedUrl(url)) {
      reject(new WidgetError("invalid_response", "Wiktionary returned an unexpected response."));
      return;
    }

    const req = https.get(url, {
      headers: {
        Accept: "application/json",
        "User-Agent": USER_AGENT,
      },
      timeout: timeoutMs,
    }, (res) => {
      if (res.statusCode === 404) {
        res.resume();
        reject(new WidgetError("not_found", "Wiktionary could not find that page."));
        return;
      }
      if (res.statusCode === 429) {
        res.resume();
        reject(new WidgetError("rate_limited", "Wiktionary is rate-limiting requests. Try again later."));
        return;
      }
      if (res.statusCode >= 300) {
        res.resume();
        reject(new WidgetError("api_error", `Wiktionary returned HTTP ${res.statusCode}.`));
        return;
      }

      const contentLength = parseInt(res.headers["content-length"], 10);
      if (Number.isFinite(contentLength) && contentLength > MAX_RESPONSE_BYTES) {
        res.resume();
        reject(new WidgetError("invalid_response", "Wiktionary returned an unexpected response."));
        return;
      }

      let payload = "";
      let rejected = false;
      res.setEncoding("utf8");
      res.on("data", (chunk) => {
        if (rejected) return;
        payload += chunk;
        if (payload.length > MAX_RESPONSE_BYTES) {
          rejected = true;
          res.destroy();
          reject(new WidgetError("invalid_response", "Wiktionary returned an unexpected response."));
        }
      });
      res.on("end", () => {
        if (rejected) return;
        try {
          const data = JSON.parse(payload);
          if (typeof data !== "object" || data === null || Array.isArray(data)) {
            reject(new WidgetError("invalid_response", "Wiktionary returned an unexpected response."));
            return;
          }
          resolve(data);
        } catch (err) {
          reject(new WidgetError("invalid_response", "Wiktionary returned an unreadable response."));
        }
      });
    });

    req.on("error", () => {
      reject(new WidgetError("network_error", "Could not reach Wiktionary."));
    });
    req.on("timeout", () => {
      req.destroy();
      reject(new WidgetError("network_error", "Request to Wiktionary timed out."));
    });
  });
}

function firstText(...values) {
  for (const value of values) {
    const text = String(value || "").trim();
    if (text) return text;
  }
  return "";
}

function displayText(...values) {
  const text = firstText(...values)
    .replace(/<[^>]*>/g, "")
    .replace(/[<>]/g, "")
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, "")
    .replace(/[\u202A-\u202E\u2066-\u2069]/g, "");
  return text.length > MAX_DISPLAY_LENGTH ? text.substring(0, MAX_DISPLAY_LENGTH) : text;
}

function extractCjk(text) {
  const chars = [];
  for (const char of String(text || "")) {
    const code = char.codePointAt(0);
    if (code && isCjkCodePoint(code)) chars.push(char);
  }
  return chars;
}

function firstCjk(text) {
  const chars = extractCjk(text);
  return chars.length ? chars[0] : "";
}

function stripWiki(text) {
  let t = String(text || "");
  t = t.replace(/\{\{[^}]*\}\}/g, " ");
  t = t.replace(/\[\[([^|\]]+)\|([^\]]+)\]\]/g, "$2");
  t = t.replace(/\[\[([^\]]+)\]\]/g, "$1");
  t = t.replace(/'{2,}/g, "");
  t = t.replace(/<[^>]+>/g, " ");
  t = t.replace(/&nbsp;/g, " ");
  t = t.replace(/\(\s*\)/g, "");
  t = t.replace(/\s{2,}/g, " ").trim();
  t = t.replace(/[;:,]\s*$/g, "");
  return t;
}

function section(wikitext, heading) {
  const source = String(wikitext || "");
  const start = source.search(new RegExp("^==\\s*" + heading + "\\s*==\\s*$", "im"));
  if (start < 0) return "";
  const rest = source.slice(start);
  const next = rest.slice(2).search(/\n==[^=]/);
  return next < 0 ? rest : rest.slice(0, next + 2);
}

function parseNamedParams(body) {
  const params = {};
  for (const part of String(body || "").split("|")) {
    const eq = part.indexOf("=");
    if (eq < 0) continue;
    params[part.slice(0, eq).trim()] = part.slice(eq + 1).trim();
  }
  return params;
}

function matchTemplate(name, wikitext) {
  const re = new RegExp("\\{\\{\\s*" + name + "\\|([\\s\\S]*?)\\}\\}", "i");
  return String(wikitext || "").match(re);
}

function wikitextUrl(title) {
  const params = new URLSearchParams({
    action: "parse",
    page: title,
    prop: "wikitext",
    format: "json",
    formatversion: "2",
    redirects: "1",
  });
  return API_ORIGIN + API_PATH + "?" + params.toString();
}

function dictionaryUrl(character) {
  return "https://www.mdbg.net/chinese/dictionary?page=worddict&wdrst=0&wdqb="
    + encodeURIComponent(character);
}

function localDateString(now = new Date()) {
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return year + "-" + month + "-" + day;
}

function hashDate(dateStr) {
  let hash = 2166136261;
  const text = String(dateStr || "");
  for (let i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function formatHskLevel(level) {
  const match = String(level || "").trim().match(/I-(\d+)/i);
  return match ? "HSK " + match[1] : displayText(level);
}

function parseHskAppendix(wikitext, allowedLevels = DEFAULT_LEVELS) {
  const allowed = new Set((allowedLevels || DEFAULT_LEVELS).map((level) => String(level).trim()));
  const bySimplified = new Map();
  const tradToSimp = {};
  const rowRe = /\{\{lang\|zh\|([^}]+)\}\}\s*\|\|\s*\{\{lang\|zh\|([^}]+)\}\}\s*\|\|\s*([^|\n]+)\s*\|\|\s*([^|\n]+)/g;
  let match;
  while ((match = rowRe.exec(String(wikitext || ""))) !== null) {
    const traditionalChars = extractCjk(match[1]);
    const simplified = firstCjk(match[2]);
    const pinyin = displayText(match[3]).split(/[,;]/)[0].trim();
    const level = String(match[4] || "").trim();
    if (!simplified || !allowed.has(level)) continue;

    for (const trad of traditionalChars) tradToSimp[trad] = simplified;
    tradToSimp[simplified] = simplified;

    const existing = bySimplified.get(simplified);
    if (!existing || level < existing.level) {
      bySimplified.set(simplified, {
        simplified,
        traditional: traditionalChars[0] || simplified,
        pinyin,
        level,
      });
    }
  }

  return {
    pool: Array.from(bySimplified.values()),
    tradToSimp,
  };
}

function toSimplified(text, tradToSimp) {
  const map = tradToSimp || {};
  return Array.from(String(text || "")).map((char) => map[char] || char).join("");
}

function extractZhSee(wikitext) {
  const match = String(wikitext || "").match(/\{\{\s*zh-see\|([^}|]+)/i);
  if (!match) return "";
  const chars = extractCjk(match[1]).join("");
  return chars || displayText(match[1]);
}

function extractHanChar(wikitext) {
  const match = matchTemplate("Han char", wikitext);
  if (!match) return { radical: "", strokes: "", ids: "" };
  const params = parseNamedParams(match[1]);
  const strokes = parseInt(params.sn, 10);
  return {
    radical: firstCjk(params.rad) || displayText(params.rad),
    strokes: Number.isFinite(strokes) ? strokes : "",
    ids: firstText(params.ids),
  };
}

function extractIdsComponents(ids) {
  const seen = new Set();
  const components = [];
  for (const char of extractCjk(ids)) {
    const code = char.codePointAt(0);
    if (isIdcCodePoint(code) || seen.has(char)) continue;
    seen.add(char);
    components.push(char);
    if (components.length >= MAX_COMPONENTS) break;
  }
  return components;
}

function extractMandarinPinyin(wikitext) {
  const match = String(wikitext || "").match(/\{\{zh-pron[\s\S]*?\|m=([^\n|}]+)/);
  if (!match) return "";
  return displayText(match[1].split(",")[0]);
}

function extractSimplifiedForm(wikitext) {
  const forms = matchTemplate("zh-forms", wikitext);
  if (!forms) return "";
  const params = parseNamedParams(forms[1]);
  return firstCjk(params.s);
}

function extractDefinitions(wikitext) {
  const chinese = section(wikitext, "Chinese") || String(wikitext || "");
  const glosses = [];
  const lineRe = /^#(?![#*:])\s*(.+)$/gm;
  let match;
  while ((match = lineRe.exec(chinese)) !== null) {
    const raw = match[1];
    if (/\{\{\s*alt form\|/i.test(raw) || /\{\{\s*zh-used\|/i.test(raw)) continue;
    if (/\{\{\s*lb\|zh\|(?:obs-std|obsolete|historical|archaic|Cantonese)/i.test(raw)
      && !/\{\{\s*lb\|zh\|(?:transitive|intransitive|noun)/i.test(raw)) {
      continue;
    }
    const gloss = stripWiki(raw).replace(/^[#*:]\s*/, "");
    if (!gloss || gloss.length < 2) continue;
    glosses.push(gloss);
    if (glosses.length >= MAX_GLOSSES) break;
  }
  return glosses.join("; ");
}

function extractEtymology(wikitext) {
  const simp = matchTemplate("Han simp", wikitext);
  if (simp) {
    const source = firstCjk(simp[1].split("|")[0]);
    if (source) return "Simplified from " + source;
  }
  const compound = matchTemplate("Han compound", wikitext);
  if (compound) {
    const params = parseNamedParams(compound[1]);
    if (params.ls === "psc") return "Phono-semantic compound";
    if (params.ls === "ic" || params.ls === "ids") return "Ideogrammic compound";
    return "Compound character";
  }
  return "";
}

function extractZhCoWords(wikitext, tradToSimp, pinyinByChar) {
  const words = [];
  const seen = new Set();
  const patterns = [
    /\{\{\s*zh-co\|([^}|]+)\|([^}]+)\}\}/gi,
    /\{\{\s*zh-l\|([^}|]+)\|([^}]+)\}\}/gi,
  ];
  for (const re of patterns) {
    let match;
    while ((match = re.exec(String(wikitext || ""))) !== null) {
      const simplified = toSimplified(extractCjk(match[1]).join(""), tradToSimp);
      if (simplified.length < 2 || simplified.length > 3 || seen.has(simplified)) continue;
      const meaning = displayText(stripWiki(match[2]));
      if (!meaning) continue;
      seen.add(simplified);
      words.push({
        word: displayText(simplified),
        pinyin: wordPinyin(simplified, pinyinByChar),
        meaning,
      });
    }
  }
  return words;
}

function extractCompoundWords(wikitext, tradToSimp, pinyinByChar, already) {
  const words = already ? already.slice() : [];
  const seen = new Set(words.map((item) => item.word));
  const col = String(wikitext || "").match(/\{\{\s*col\d*\|zh\|([^}]+)\}\}/i)
    || String(wikitext || "").match(/\{\{\s*zh-der\|([^}]+)\}\}/i);
  if (!col) return words;

  for (const part of col[1].split("|")) {
    if (words.length >= MAX_WORD_CANDIDATES) break;
    if (part.includes("=")) continue;
    const simplified = toSimplified(extractCjk(part).join(""), tradToSimp);
    if (simplified.length < 2 || simplified.length > 3 || seen.has(simplified)) continue;
    seen.add(simplified);
    words.push({
      word: displayText(simplified),
      pinyin: wordPinyin(simplified, pinyinByChar),
      meaning: "",
    });
  }
  return words;
}

function wordScore(word, focus, pinyinByChar) {
  const chars = Array.from(String(word || ""));
  if (!chars.length || !chars.includes(focus)) return -1;
  let known = 0;
  for (const char of chars) {
    if (char === focus || (pinyinByChar && pinyinByChar[char])) known++;
  }
  const knownRatio = known / chars.length;
  if (chars.length > 2 && knownRatio < 1) return -1;
  const lengthBonus = chars.length === 2 ? 0.25 : 0;
  const pinyinBonus = wordPinyin(word, pinyinByChar) ? 0.2 : 0;
  return knownRatio + lengthBonus + pinyinBonus;
}

function rankWords(words, focus, pinyinByChar) {
  return (words || [])
    .map((item) => {
      let score = wordScore(item.word, focus, pinyinByChar);
      if (score >= 0 && firstText(item.meaning)) score += 1;
      return Object.assign({}, item, { _score: score });
    })
    .filter((item) => item._score >= 0.6)
    .sort((a, b) => b._score - a._score)
    .slice(0, MAX_WORD_CANDIDATES)
    .map((item) => {
      delete item._score;
      return item;
    });
}

function wordsWithMeanings(words) {
  return (words || [])
    .filter((item) => firstText(item && item.meaning) && firstText(item && item.word))
    .slice(0, MAX_WORDS)
    .map((item) => ({
      word: displayText(item.word),
      pinyin: displayText(item.pinyin),
      meaning: displayText(String(item.meaning).split(";")[0]),
    }));
}

function simpToTradMap(tradToSimp) {
  const map = {};
  for (const [trad, simp] of Object.entries(tradToSimp || {})) {
    if (simp && !map[simp]) map[simp] = trad;
  }
  return map;
}

function toTraditional(text, simpToTrad) {
  const map = simpToTrad || {};
  return Array.from(String(text || "")).map((char) => map[char] || char).join("");
}

function shortWordGloss(text) {
  return displayText(String(text || "").split(";")[0].split(",")[0].trim());
}

function wordPinyin(word, pinyinByChar) {
  const map = pinyinByChar || {};
  const parts = [];
  for (const char of Array.from(String(word || ""))) {
    if (map[char]) parts.push(map[char]);
  }
  return parts.length === Array.from(String(word || "")).length ? parts.join(" ") : "";
}

function pinyinMapFromPool(pool) {
  const map = {};
  for (const item of pool || []) {
    if (item.simplified && item.pinyin && !map[item.simplified]) {
      map[item.simplified] = item.pinyin;
    }
  }
  return map;
}

function emptyCharacter(overrides) {
  return Object.assign({
    ok: false,
    stale: false,
    shuffled: false,
    date: "",
    character: "",
    traditional: "",
    pinyin: "",
    meaning: "",
    hskLevel: "",
    hskLabel: "",
    strokes: "",
    radical: "",
    etymology: "",
    components: [],
    words: [],
    dictionaryUrl: "",
    fetchedAt: "",
    error: "",
    errorCode: "",
  }, overrides || {});
}

function sanitizeItem(item) {
  if (!item || typeof item !== "object") return item;
  sanitizeField(item, "character");
  sanitizeField(item, "pinyin");
  sanitizeField(item, "meaning");
  sanitizeField(item, "word");
  return item;
}

function sanitizeField(obj, key) {
  if (!obj || !Object.prototype.hasOwnProperty.call(obj, key) || obj[key] == null) return;
  obj[key] = displayText(obj[key]);
}

function sanitizeSnapshot(data) {
  if (typeof data !== "object" || data === null) return data;
  const keys = [
    "error", "errorCode", "date", "character", "traditional", "pinyin",
    "meaning", "hskLevel", "hskLabel", "etymology", "radical", "dictionaryUrl",
    "fetchedAt",
  ];
  for (const key of keys) sanitizeField(data, key);
  if (data.strokes !== undefined && data.strokes !== "") {
    const strokes = parseInt(data.strokes, 10);
    data.strokes = Number.isFinite(strokes) ? strokes : "";
  }
  if (Array.isArray(data.components)) {
    data.components = data.components.slice(0, MAX_COMPONENTS).map((item) => sanitizeItem({ ...item }));
  }
  if (Array.isArray(data.words)) {
    data.words = data.words.slice(0, MAX_WORDS).map((item) => sanitizeItem({ ...item }));
  }
  return data;
}

function pickFromPool(pool, dateStr, exclude) {
  const list = Array.isArray(pool) ? pool : [];
  if (!list.length) {
    throw new WidgetError("invalid_response", "Wiktionary did not return an HSK character list.");
  }
  const excluded = new Set(exclude || []);
  const available = list.filter((item) => !excluded.has(item.simplified));
  const source = available.length ? available : list;
  const index = hashDate(dateStr) % source.length;
  return source[index];
}

function pickRandom(pool, exclude) {
  const list = Array.isArray(pool) ? pool : [];
  if (!list.length) {
    throw new WidgetError("invalid_response", "Wiktionary did not return an HSK character list.");
  }
  const excluded = new Set(exclude || []);
  const available = list.filter((item) => !excluded.has(item.simplified));
  const source = available.length ? available : list;
  return source[Math.floor(Math.random() * source.length)];
}

function parseWikitextResponse(data, title) {
  const parse = data && data.parse;
  if (!parse || typeof parse !== "object") {
    throw new WidgetError("not_found", 'Wiktionary has no page for "' + displayText(title) + '".');
  }
  const text = typeof parse.wikitext === "string"
    ? parse.wikitext
    : (parse.wikitext && parse.wikitext["*"]) || "";
  if (!text) {
    throw new WidgetError("invalid_response", "Wiktionary returned an empty page.");
  }
  return { title: firstText(parse.title, title), wikitext: text };
}

async function fetchWikitext(title, getJsonFn, timeoutMs) {
  const data = await getJsonFn(wikitextUrl(title), timeoutMs);
  return parseWikitextResponse(data, title);
}

async function loadPool(getJsonFn, timeoutMs, cacheDir, force) {
  const poolPath = path.join(cacheDir, "pool.json");
  if (!force) {
    try {
      const cached = JSON.parse(fs.readFileSync(poolPath, "utf8"));
      if (cached && Array.isArray(cached.pool) && cached.pool.length && cached.tradToSimp) {
        const age = Date.now() / 1000 - Number(cached.savedAt || 0);
        if (age >= 0 && age < 60 * 60 * 24) return cached;
      }
    } catch (err) {}
  }

  const page = await fetchWikitext(HSK_APPENDIX, getJsonFn, timeoutMs);
  const parsed = parseHskAppendix(page.wikitext, DEFAULT_LEVELS);
  if (!parsed.pool.length) {
    throw new WidgetError("invalid_response", "Wiktionary did not return an HSK character list.");
  }
  const wrapper = {
    savedAt: Date.now() / 1000,
    pool: parsed.pool,
    tradToSimp: parsed.tradToSimp,
  };
  writeJson(poolPath, wrapper);
  return wrapper;
}

async function lookupComponent(title, getJsonFn, timeoutMs) {
  try {
    const page = await fetchWikitext(title, getJsonFn, timeoutMs);
    const lemma = extractZhSee(page.wikitext);
    let wikitext = page.wikitext;
    if (lemma && lemma !== title) {
      try {
        const followed = await fetchWikitext(lemma, getJsonFn, timeoutMs);
        wikitext += "\n" + followed.wikitext;
      } catch (err) {}
    }
    const meaning = extractDefinitions(wikitext)
      .split(";")[0]
      .split(",")[0]
      .replace(/\s+,/g, ",")
      .trim();
    return {
      character: displayText(title),
      pinyin: extractMandarinPinyin(wikitext),
      meaning: displayText(meaning),
    };
  } catch (err) {
    return { character: displayText(title), pinyin: "", meaning: "" };
  }
}

async function lookupWord(title, getJsonFn, timeoutMs, tradToSimp) {
  const titles = [];
  const simplified = toSimplified(title, tradToSimp);
  const traditional = toTraditional(simplified, simpToTradMap(tradToSimp));
  for (const candidate of [simplified, traditional, title]) {
    if (candidate && !titles.includes(candidate)) titles.push(candidate);
  }

  for (const pageTitle of titles) {
    try {
      const page = await fetchWikitext(pageTitle, getJsonFn, timeoutMs);
      let wikitext = page.wikitext;
      const lemma = extractZhSee(page.wikitext);
      if (lemma && lemma !== pageTitle) {
        try {
          const followed = await fetchWikitext(lemma, getJsonFn, timeoutMs);
          wikitext += "\n" + followed.wikitext;
        } catch (err) {}
      }
      const chinese = section(wikitext, "Chinese");
      if (!chinese) continue;
      const meaning = shortWordGloss(extractDefinitions(chinese));
      if (!meaning) continue;
      return {
        word: displayText(simplified || pageTitle),
        pinyin: extractMandarinPinyin(chinese),
        meaning,
      };
    } catch (err) {}
  }
  return { word: displayText(simplified || title), pinyin: "", meaning: "" };
}

async function fillWordMeanings(words, getJsonFn, timeoutMs, tradToSimp, pinyinByChar) {
  const filled = [];
  for (const item of words || []) {
    if (filled.length >= MAX_WORDS) break;
    let meaning = shortWordGloss(item.meaning);
    let pinyin = displayText(item.pinyin);
    if (!meaning) {
      const looked = await lookupWord(item.word, getJsonFn, timeoutMs, tradToSimp);
      meaning = looked.meaning;
      if (!pinyin) pinyin = displayText(looked.pinyin);
    }
    if (!meaning) continue;
    filled.push({
      word: displayText(item.word),
      pinyin: pinyin || wordPinyin(item.word, pinyinByChar),
      meaning,
    });
  }
  return filled;
}

async function lookupCharacter(character, poolItem, pool, getJsonFn, timeoutMs) {
  const page = await fetchWikitext(character, getJsonFn, timeoutMs);
  let wikitext = page.wikitext;
  const see = extractZhSee(page.wikitext);
  let lemmaPage = page;
  if (see && see !== character) {
    lemmaPage = await fetchWikitext(see, getJsonFn, timeoutMs);
    wikitext += "\n" + lemmaPage.wikitext;
  }

  const han = extractHanChar(page.wikitext) ;
  const hanLemma = extractHanChar(lemmaPage.wikitext);
  const radical = han.radical || hanLemma.radical;
  const strokes = han.strokes || hanLemma.strokes;
  const ids = han.ids || hanLemma.ids;
  const pinyinByChar = pinyinMapFromPool(pool.pool);
  const chinese = section(lemmaPage.wikitext, "Chinese") || lemmaPage.wikitext;
  const words = await fillWordMeanings(
    rankWords(
      extractCompoundWords(
        chinese,
        pool.tradToSimp,
        pinyinByChar,
        extractZhCoWords(chinese, pool.tradToSimp, pinyinByChar)
      ),
      character,
      pinyinByChar
    ),
    getJsonFn,
    timeoutMs,
    pool.tradToSimp,
    pinyinByChar
  );

  const componentChars = extractIdsComponents(ids).filter((char) => char !== character);
  const components = [];
  for (const part of componentChars) {
    const item = await lookupComponent(part, getJsonFn, timeoutMs);
    const code = item.character.codePointAt(0) || 0;
    if (!item.meaning && code > 0x9FFF) continue;
    components.push(item);
  }

  const traditional = firstCjk(poolItem && poolItem.traditional)
    || see
    || character;
  const meaning = extractDefinitions(chinese);
  const pinyin = firstText(
    extractMandarinPinyin(chinese),
    poolItem && poolItem.pinyin
  );

  if (!pinyin && !meaning) {
    throw new WidgetError("invalid_response", "Wiktionary did not include Mandarin data for that character.");
  }

  return sanitizeSnapshot({
    ok: true,
    stale: false,
    shuffled: false,
    character: displayText(character),
    traditional: displayText(traditional),
    pinyin: displayText(pinyin),
    meaning: displayText(meaning),
    hskLevel: displayText(poolItem && poolItem.level),
    hskLabel: formatHskLevel(poolItem && poolItem.level),
    strokes: strokes,
    radical: displayText(radical),
    etymology: displayText(extractEtymology(page.wikitext + "\n" + lemmaPage.wikitext)),
    components,
    words,
    dictionaryUrl: dictionaryUrl(character),
    fetchedAt: new Date().toISOString(),
    error: "",
    errorCode: "",
  });
}

function defaultCacheDir() {
  const home = os.homedir();
  const cacheHome = process.env.XDG_CACHE_HOME || path.join(home, ".cache");
  return path.join(cacheHome, "omarchy-hanzi");
}

function expandUser(p) {
  if (p.startsWith("~")) return path.join(os.homedir(), p.slice(1));
  return p;
}

function writeJson(filePath, data) {
  const dir = path.dirname(filePath);
  fs.mkdirSync(dir, { recursive: true });
  const tempPath = path.join(dir, "." + path.basename(filePath) + "-" + Math.random().toString(36).slice(2));
  try {
    fs.writeFileSync(tempPath, JSON.stringify(data), "utf8");
    fs.chmodSync(tempPath, 0o600);
    fs.renameSync(tempPath, filePath);
  } catch (err) {
    try { if (fs.existsSync(tempPath)) fs.unlinkSync(tempPath); } catch (_) {}
    throw err;
  }
}

function readJson(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (err) {
    return null;
  }
}

async function acquireLock(lockPath) {
  const maxRetries = 50;
  for (let i = 0; i < maxRetries; i++) {
    try {
      const fd = fs.openSync(lockPath, "wx");
      fs.writeSync(fd, String(process.pid));
      fs.closeSync(fd);
      return true;
    } catch (err) {
      if (err.code !== "EEXIST") return false;
      try {
        const pid = parseInt(fs.readFileSync(lockPath, "utf8").trim(), 10);
        if (Number.isFinite(pid)) {
          try { process.kill(pid, 0); } catch (dead) {
            if (dead.code === "ESRCH") {
              fs.unlinkSync(lockPath);
              continue;
            }
          }
        }
      } catch (_) {}
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }
  return false;
}

function releaseLock(lockPath) {
  try { fs.unlinkSync(lockPath); } catch (err) {}
}

function errorPayload(exc) {
  return emptyCharacter({
    error: displayText(exc && exc.message) || "Wiktionary request failed.",
    errorCode: firstText(exc && exc.code),
    fetchedAt: "",
  });
}

async function run(args, getJsonFn = getJson) {
  const cacheDir = expandUser(args.cache || defaultCacheDir());
  fs.mkdirSync(cacheDir, { recursive: true });
  const todayPath = path.join(cacheDir, "today.json");
  const lockPath = todayPath + ".lock";
  const dateStr = firstText(args.date) || localDateString();
  const timeoutSec = parseFloat(args.timeout !== undefined ? args.timeout : 20);
  const timeoutMs = (Number.isFinite(timeoutSec) ? timeoutSec : 20) * 1000;
  const shuffle = args.shuffle === true;
  const force = args.force === true;
  const requested = firstCjk(args.character);

  const lockAcquired = await acquireLock(lockPath);
  if (!lockAcquired) {
    return errorPayload(new WidgetError("lock_failed", "Could not acquire file lock."));
  }

  try {
    const previous = readJson(todayPath);
    const sameDay = previous && previous.date === dateStr && previous.data && previous.data.ok === true;

    if (!force && !shuffle && !requested && sameDay) {
      return sanitizeSnapshot({ ...previous.data, date: dateStr, shuffled: previous.shuffled === true });
    }

    try {
      const pool = await loadPool(getJsonFn, timeoutMs, cacheDir, force && !sameDay);
      const used = sameDay && Array.isArray(previous.used) ? previous.used.slice() : [];
      let item;
      if (requested) {
        item = pool.pool.find((entry) => entry.simplified === requested)
          || { simplified: requested, traditional: requested, pinyin: "", level: "" };
      } else if (shuffle) {
        item = pickRandom(pool.pool, used);
      } else {
        item = pickFromPool(pool.pool, dateStr, []);
      }

      const snapshot = await lookupCharacter(item.simplified, item, pool, getJsonFn, timeoutMs);
      snapshot.date = dateStr;
      snapshot.shuffled = shuffle === true && !requested;
      if (!used.includes(snapshot.character)) used.push(snapshot.character);

      writeJson(todayPath, {
        date: dateStr,
        shuffled: snapshot.shuffled,
        used,
        data: snapshot,
      });
      return snapshot;
    } catch (exc) {
      if (sameDay) {
        const stale = sanitizeSnapshot({ ...previous.data });
        stale.stale = true;
        stale.date = dateStr;
        stale.error = displayText(exc.message) || "Wiktionary request failed.";
        stale.errorCode = firstText(exc.code);
        return stale;
      }
      return errorPayload(exc);
    }
  } finally {
    releaseLock(lockPath);
  }
}

async function main() {
  const options = {
    cache: { type: "string" },
    timeout: { type: "string" },
    force: { type: "boolean" },
    shuffle: { type: "boolean" },
    pretty: { type: "boolean" },
    character: { type: "string" },
    date: { type: "string" },
  };

  let args;
  try {
    args = parseArgs({ options, strict: false }).values;
  } catch (err) {
    args = {};
  }

  const result = await run(args);
  console.log(args.pretty ? JSON.stringify(result, null, 2) : JSON.stringify(result));
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

module.exports = {
  WidgetError,
  isAllowedUrl,
  getJson,
  firstText,
  displayText,
  extractCjk,
  firstCjk,
  stripWiki,
  section,
  wikitextUrl,
  dictionaryUrl,
  localDateString,
  hashDate,
  formatHskLevel,
  parseHskAppendix,
  toSimplified,
  extractZhSee,
  extractHanChar,
  extractIdsComponents,
  extractMandarinPinyin,
  extractSimplifiedForm,
  extractDefinitions,
  extractEtymology,
  extractZhCoWords,
  extractCompoundWords,
  rankWords,
  wordsWithMeanings,
  fillWordMeanings,
  lookupWord,
  wordPinyin,
  pinyinMapFromPool,
  sanitizeSnapshot,
  pickFromPool,
  pickRandom,
  parseWikitextResponse,
  lookupCharacter,
  run,
};
