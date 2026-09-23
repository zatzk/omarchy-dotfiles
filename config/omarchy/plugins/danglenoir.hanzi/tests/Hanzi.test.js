const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const api = require("../Hanzi.js");

const HSK_FIXTURE = `
{| class="wikitable sortable"
|-
! Traditional !! Simplified !! Pinyin !! Level !! Notes
|-
|{{lang|zh|[[一]]}} || {{lang|zh|一}} || yī || I-1 ||
|-
|{{lang|zh|[[學]]}} || {{lang|zh|学}} || xué || I-1 ||
|-
|{{lang|zh|[[人]]}} || {{lang|zh|人}} || rén || I-1 ||
|-
|{{lang|zh|[[好]]}} || {{lang|zh|好}} || hǎo || I-2 ||
|-
|{{lang|zh|[[習]]}} || {{lang|zh|习}} || xí || I-3 ||
|-
|{{lang|zh|[[龍]]}} || {{lang|zh|龙}} || lóng || II-4 ||
|}
`;

const XUE_PAGE = `{{also|學}}
{{character info}}

==Translingual==
===Han character===
{{Han char|rn=39|rad=子|as=05|sn=8|four=|canj=FBND|ids=⿱𰃮子}}
{{Han simp|學|f=𪜯|t=𰃮}}

==Chinese==
===Etymology 1===
{{zh-see|學|sv}}
`;

const XUE_TRAD = `{{also|学}}
==Translingual==
===Han character===
{{Han char|rn=39|rad=子|as=13|sn=16|ids=⿱𦥯子}}

==Chinese==
{{zh-forms|s=学}}
====Pronunciation====
{{zh-pron
|m=xué,xiáo,1nb=literary,1nc=standard in Mainland and Taiwan
|c=hok6
|cat=v,n,suffix
}}

====Definitions====
{{head|zh|hanzi}}

# {{lb|zh|obs-std}} to [[comprehend]]; to [[realise]]
# {{lb|zh|transitive}} to [[learn]]; to [[study]]
# [[school]]
# [[learning]]; [[knowledge]]
#: {{zh-co|上學|to go to '''school'''}}
#: {{zh-co|小學|primary '''school'''}}
#: {{zh-co|學習|to study; to learn}}

====Compounds====
{{col3|zh|下學|上學|中學|化學|同學|大學|學生|學校|學習}}

==Japanese==
===Kanji===
# [[education]]
`;

const ZI_PAGE = `==Chinese==
{{zh-pron
|m=zǐ
}}
====Definitions====
# [[child]]; [[son]]
`;

const COVER_PAGE = `==Chinese==
{{zh-pron
|m=mì
}}
====Definitions====
# [[cover]]
`;

function pages() {
  return {
    "Appendix:HSK_list_of_Mandarin_words_v3.0/characters": HSK_FIXTURE,
    "学": XUE_PAGE,
    "學": XUE_TRAD,
    "子": ZI_PAGE,
    "𰃮": COVER_PAGE,
    "一": `==Chinese==\n{{zh-pron\n|m=yī\n}}\n====Definitions====\n# [[one]]\n`,
    "人": `==Chinese==\n{{zh-pron\n|m=rén\n}}\n====Definitions====\n# [[person]]; [[people]]\n`,
    "好": `==Chinese==\n{{zh-pron\n|m=hǎo\n}}\n====Definitions====\n# [[good]]\n`,
    "习": `==Chinese==\n{{zh-see|習|sv}}\n{{Han char|rad=乙|sn=3|ids=习}}\n`,
    "習": `==Chinese==\n{{zh-forms|s=习}}\n{{zh-pron\n|m=xí\n}}\n====Definitions====\n# to [[practice]]\n`,
  };
}

function mockGetJson(map) {
  return async function getJson(url) {
    const parsed = new URL(url);
    const title = parsed.searchParams.get("page");
    if (!Object.prototype.hasOwnProperty.call(map, title)) {
      throw new api.WidgetError("not_found", "missing " + title);
    }
    return { parse: { title, wikitext: map[title] } };
  };
}

test("isAllowedUrl accepts only Wiktionary HTTPS", () => {
  assert.strictEqual(api.isAllowedUrl("https://en.wiktionary.org/w/api.php"), true);
  assert.strictEqual(api.isAllowedUrl("http://en.wiktionary.org/w/api.php"), false);
  assert.strictEqual(api.isAllowedUrl("https://en.wiktionary.org.evil.example/x"), false);
  assert.strictEqual(api.isAllowedUrl("https://hanzicraft.com/character/学"), false);
});

test("parseHskAppendix keeps elementary levels and maps traditional", () => {
  const parsed = api.parseHskAppendix(HSK_FIXTURE);
  const byChar = Object.fromEntries(parsed.pool.map((item) => [item.simplified, item]));
  assert.ok(byChar["学"]);
  assert.strictEqual(byChar["学"].traditional, "學");
  assert.strictEqual(byChar["学"].pinyin, "xué");
  assert.strictEqual(byChar["学"].level, "I-1");
  assert.ok(!byChar["龙"]);
  assert.strictEqual(parsed.tradToSimp["學"], "学");
  assert.strictEqual(parsed.tradToSimp["習"], "习");
});

test("hashDate is stable and pickFromPool is deterministic", () => {
  const parsed = api.parseHskAppendix(HSK_FIXTURE);
  assert.strictEqual(api.hashDate("2026-08-21"), api.hashDate("2026-08-21"));
  const first = api.pickFromPool(parsed.pool, "2026-08-21");
  const second = api.pickFromPool(parsed.pool, "2026-08-21");
  assert.strictEqual(first.simplified, second.simplified);
});

test("extractors read zh-see, Han char, pinyin, definitions, and words", () => {
  assert.strictEqual(api.extractZhSee(XUE_PAGE), "學");
  const han = api.extractHanChar(XUE_PAGE);
  assert.strictEqual(han.radical, "子");
  assert.strictEqual(han.strokes, 8);
  assert.deepStrictEqual(api.extractIdsComponents(han.ids), ["𰃮", "子"]);
  assert.strictEqual(api.extractMandarinPinyin(XUE_TRAD), "xué");
  const meaning = api.extractDefinitions(XUE_TRAD);
  assert.match(meaning, /learn/);
  assert.doesNotMatch(meaning, /comprehend/);
  const map = api.parseHskAppendix(HSK_FIXTURE).tradToSimp;
  const pinyinByChar = { 学: "xué", 上: "shàng", 小: "xiǎo", 习: "xí" };
  const words = api.extractZhCoWords(XUE_TRAD, map, pinyinByChar);
  assert.ok(words.some((word) => word.word === "上学"));
  assert.ok(words.some((word) => word.word === "学习"));
  assert.ok(words.every((word) => !word.word.includes("學")));
});

test("stripWiki and formatHskLevel", () => {
  assert.strictEqual(api.stripWiki("to [[learn]]; to [[study]]"), "to learn; to study");
  assert.strictEqual(api.formatHskLevel("I-1"), "HSK 1");
  assert.strictEqual(api.dictionaryUrl("学").includes("%E5%AD%A6"), true);
});

test("lookupCharacter follows zh-see and fills components", async () => {
  const pool = api.parseHskAppendix(HSK_FIXTURE);
  const item = pool.pool.find((entry) => entry.simplified === "学");
  const snapshot = await api.lookupCharacter(
    "学",
    item,
    pool,
    mockGetJson(pages()),
    1000
  );
  assert.strictEqual(snapshot.ok, true);
  assert.strictEqual(snapshot.character, "学");
  assert.strictEqual(snapshot.pinyin, "xué");
  assert.match(snapshot.meaning, /learn/);
  assert.strictEqual(snapshot.hskLabel, "HSK 1");
  assert.strictEqual(snapshot.strokes, 8);
  assert.strictEqual(snapshot.radical, "子");
  assert.ok(snapshot.components.some((part) => part.character === "子" && /child/.test(part.meaning)));
  assert.ok(snapshot.words.length <= 3);
  assert.ok(snapshot.words.length >= 1);
  assert.ok(snapshot.words.every((word) => word.meaning));
  assert.ok(snapshot.words.some((word) => word.word === "学生" || word.word === "学习" || word.word === "上学"));
  assert.match(snapshot.dictionaryUrl, /mdbg\.net/);
});

test("wordsWithMeanings drops empty glosses and caps at three", () => {
  const kept = api.wordsWithMeanings([
    { word: "早晨", pinyin: "zǎo chén", meaning: "morning" },
    { word: "凌晨", pinyin: "", meaning: "" },
    { word: "明晨", pinyin: "míng chén", meaning: "tomorrow morning" },
    { word: "侵晨", pinyin: "", meaning: "just before dawn" },
    { word: "拂晨", pinyin: "", meaning: "dawn" },
  ]);
  assert.strictEqual(kept.length, 3);
  assert.ok(kept.every((item) => item.meaning));
  assert.deepStrictEqual(kept.map((item) => item.word), ["早晨", "明晨", "侵晨"]);
});

test("fillWordMeanings looks up missing glosses and skips the rest", async () => {
  const getJson = mockGetJson({
    "早晨": "==Chinese==\n{{zh-pron\n|m=zǎochén\n}}\n====Definitions====\n# [[morning]]\n",
    "凌晨": "==Chinese==\n{{zh-pron\n|m=língchén\n}}\n====Definitions====\n# before [[dawn]]\n",
    "史晨碑": "==Japanese==\n# a stele\n",
  });
  const filled = await api.fillWordMeanings(
    [
      { word: "早晨", pinyin: "zǎo chén", meaning: "" },
      { word: "史晨碑", pinyin: "", meaning: "" },
      { word: "凌晨", pinyin: "", meaning: "" },
    ],
    getJson,
    1000,
    {},
    { "早": "zǎo", "晨": "chén", "凌": "líng" }
  );
  assert.strictEqual(filled.length, 2);
  assert.strictEqual(filled[0].word, "早晨");
  assert.match(filled[0].meaning, /morning/i);
  assert.strictEqual(filled[1].word, "凌晨");
  assert.match(filled[1].meaning, /dawn/i);
});

test("run caches today and shuffle picks a different character", async () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "hanzi-tests-"));
  const getJson = mockGetJson(pages());
  const first = await api.run({ cache: tempDir, date: "2026-08-21" }, getJson);
  assert.strictEqual(first.ok, true);
  const cached = await api.run({ cache: tempDir, date: "2026-08-21" }, async () => {
    throw new Error("network should not be used");
  });
  assert.strictEqual(cached.character, first.character);

  const shuffled = await api.run({ cache: tempDir, date: "2026-08-21", shuffle: true }, getJson);
  assert.strictEqual(shuffled.ok, true);
  assert.strictEqual(shuffled.shuffled, true);
  if (api.parseHskAppendix(HSK_FIXTURE).pool.length > 1) {
    assert.notStrictEqual(shuffled.character, first.character);
  }
});

test("run returns stale snapshot when a later fetch fails", async () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "hanzi-tests-"));
  const first = await api.run({ cache: tempDir, date: "2026-08-21" }, mockGetJson(pages()));
  assert.strictEqual(first.ok, true);
  const stale = await api.run({ cache: tempDir, date: "2026-08-21", force: true }, async () => {
    throw new api.WidgetError("network_error", "Could not reach Wiktionary.");
  });
  assert.strictEqual(stale.ok, true);
  assert.strictEqual(stale.stale, true);
  assert.strictEqual(stale.character, first.character);
  assert.match(stale.error, /Wiktionary/);
});
