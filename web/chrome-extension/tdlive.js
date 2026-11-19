// ==UserScript==
// @name         TD Live for Tiger Droppings
// @namespace    https://github.com/Bayou-Brains/tigerdroppings-ios-app
// @version      1.0.0
// @description  Condensed dark reader for TigerDroppings: vote heat bars, Live mode, and resume where you left off.
// @author       Bayou-Brains
// @homepageURL  https://github.com/Bayou-Brains/tigerdroppings-ios-app
// @match        https://www.tigerdroppings.com/*
// @match        https://tigerdroppings.com/*
// @updateURL    https://raw.githubusercontent.com/Bayou-Brains/tigerdroppings-ios-app/main/web/tdlive.user.js
// @downloadURL  https://raw.githubusercontent.com/Bayou-Brains/tigerdroppings-ios-app/main/web/tdlive.user.js
// @run-at       document-start
// @grant        none
// ==/UserScript==

(function () {
  "use strict";
  // evaluateOnNewDocument / very-early document-start can run before <html> exists.
  // Ad iframes should not get the reader (Tampermonkey/extension matches already skip most of them).
  try { if (window !== window.top) return; } catch (e) { return; }
  if (window.__TD_LIVE__) return;
  window.__TD_LIVE__ = true;

  var STORAGE_KEY = "tdlive.readPositions";
  var LIVE_PREF_KEY = "tdlive.liveOn";
  var WANT_LIVE_KEY = "tdlive.wantLive";
  var MAX_STORED = 500;
  var POLL_MS = 5000;
  var POSTS_PER_PAGE = 20;

  var GREEN = { r: 33, g: 179, b: 74 };   // 0.13, 0.70, 0.29
  var RED = { r: 219, g: 43, b: 43 };     // 0.86, 0.17, 0.17

  var CSS = [
    "html.tdlive-on, html.tdlive-on body { background:#000 !important; color:#fff !important; color-scheme:dark; }",
    "html.tdlive-on body, html.tdlive-on #main, html.tdlive-on .Main, html.tdlive-on #forumcontent,",
    "html.tdlive-on .bodyR1, html.tdlive-on .body-content, html.tdlive-on .maincont, html.tdlive-on .maincont1,",
    "html.tdlive-on #mbmt, html.tdlive-on #mbind, html.tdlive-on .LNavBG, html.tdlive-on .LNav, html.tdlive-on #ContentL1,",
    "html.tdlive-on #ContentL, html.tdlive-on #topnav, html.tdlive-on .divHLogoFull, html.tdlive-on .menu-nav,",
    "html.tdlive-on .footer, html.tdlive-on #footer, html.tdlive-on .Paging, html.tdlive-on .TopicHead,",
    "html.tdlive-on .index, html.tdlive-on .flex, html.tdlive-on .flex-op, html.tdlive-on .author, html.tdlive-on .title,",
    "html.tdlive-on .lowLead, html.tdlive-on #follow, html.tdlive-on .foot1_cont, html.tdlive-on .footC,",
    "html.tdlive-on .siteNav, html.tdlive-on .mob_box, html.tdlive-on .forum-search, html.tdlive-on .forum-search__form,",
    "html.tdlive-on #confbox, html.tdlive-on .opt, html.tdlive-on .row, html.tdlive-on .LCatdiv {",
    "  background:#000 !important; color:#fff !important; border-color:#2c2c2c !important;",
    "}",
    "html.tdlive-on a, html.tdlive-on a:visited { color:#fdd023 !important; }",
    "html.tdlive-on a:hover { color:#ffe56a !important; }",
    "html.tdlive-on h1, html.tdlive-on h2, html.tdlive-on h3, html.tdlive-on h4, html.tdlive-on p,",
    "html.tdlive-on li, html.tdlive-on label,",
    "html.tdlive-on .pText, html.tdlive-on .time, html.tdlive-on .pdate, html.tdlive-on .bio, html.tdlive-on .lp,",
    "html.tdlive-on .author-ind, html.tdlive-on .middle, html.tdlive-on .col1, html.tdlive-on .col2,",
    "html.tdlive-on .col3, html.tdlive-on .col4, html.tdlive-on .col1-mt, html.tdlive-on .col2-mt,",
    "html.tdlive-on .SubjectDisplay, html.tdlive-on .MessName, html.tdlive-on .pg, html.tdlive-on .pg1,",
    "html.tdlive-on .MBNav, html.tdlive-on .bread, html.tdlive-on .foot, html.tdlive-on .hdr, html.tdlive-on .txt {",
    "  color:#fff !important;",
    "}",
    "html.tdlive-on .pText { font-size:15px !important; line-height:1.45 !important; color:#f2f2f2 !important; padding:6px 12px 8px !important; }",
    "html.tdlive-on .pText a { color:#fdd023 !important; }",
    "html.tdlive-on h1.SubjectDisplay, html.tdlive-on .SubjectDisplay {",
    "  color:#fff !important; font-size:18px !important; font-weight:650 !important; background:transparent !important;",
    "}",
    "html.tdlive-on .index h2, html.tdlive-on .index h2 a {",
    "  color:#fff !important; font-size:15px !important; font-weight:500 !important; background:transparent !important;",
    "  line-height:1.3 !important;",
    "}",
    "html.tdlive-on .index.indRow, html.tdlive-on .index.indRowAlt {",
    "  background:#000 !important; border-bottom:1px solid #474747 !important; padding:8px 10px !important;",
    "}",
    "html.tdlive-on .index.indRow:hover, html.tdlive-on .index.indRowAlt:hover { background:#111 !important; }",
    "html.tdlive-on .maincont1.indRow, html.tdlive-on .maincont1.indRowAlt {",
    "  background:#000 !important; border-bottom:1px solid #474747 !important; padding:8px 0 !important;",
    "  position:relative !important;",
    "}",
    "html.tdlive-on .TopicHead { display:none !important; }",
    "html.tdlive-on .bio, html.tdlive-on .j-top, html.tdlive-on .op-time { display:none !important; }",
    "html.tdlive-on .flex, html.tdlive-on .flex-op { padding:4px 12px 4px 14px !important; background:#000 !important; }",
    "html.tdlive-on .author, html.tdlive-on .time, html.tdlive-on .title { background:transparent !important; }",
    "html.tdlive-on .author a.RegUser { font-weight:650 !important; color:#fff !important; }",
    "html.tdlive-on .tdlive-post-op .author a.RegUser { color:#fdd023 !important; }",
    "html.tdlive-on .time, html.tdlive-on .pdate, html.tdlive-on .PostInfo, html.tdlive-on a.PostInfo {",
    "  color:#9a9a9a !important; font-size:12px !important;",
    "}",
    "html.tdlive-on .mtdivide, html.tdlive-on .divrepl, html.tdlive-on .divrepl-cont, html.tdlive-on .likes {",
    "  background:#000 !important; color:#ccc !important; border-color:#333 !important;",
    "}",
    "html.tdlive-on a.rep-button, html.tdlive-on .rep-button {",
    "  color:#ccc !important; background:#1a1a1a !important; border:1px solid #333 !important;",
    "  border-radius:4px !important; padding:3px 8px !important;",
    "}",
    "html.tdlive-on .mbThUp, html.tdlive-on .mbThDown, html.tdlive-on .mbvoted { color:#ddd !important; background:transparent !important; }",
    "html.tdlive-on blockquote.q1, html.tdlive-on blockquote {",
    "  background:#242424 !important; color:#b8b8b8 !important; border-left:3px solid #474747 !important;",
    "  padding:8px 10px !important; margin:8px 0 !important;",
    "}",
    "html.tdlive-on .QuoteLine { border-color:#474747 !important; background:#474747 !important; }",
    "html.tdlive-on .PostItalic, html.tdlive-on .editText { color:#8e8e8e !important; }",
    "html.tdlive-on .Paging, html.tdlive-on .Paging1, html.tdlive-on .PagingL, html.tdlive-on .PagingR, html.tdlive-on .PgBoardNameT {",
    "  background:#000 !important; color:#fff !important; border-color:#2c2c2c !important;",
    "}",
    "html.tdlive-on .pg, html.tdlive-on a.pg, html.tdlive-on .pg1, html.tdlive-on .pgsel, html.tdlive-on .pgsel b {",
    "  color:#fdd023 !important; background:transparent !important;",
    "}",
    "html.tdlive-on .pg.pgsel, html.tdlive-on span.pgsel { color:#fff !important; font-weight:700 !important; }",
    "html.tdlive-on .LNav a, html.tdlive-on .LNav1, html.tdlive-on .LNav li, html.tdlive-on .LNavCat, html.tdlive-on .bread2 {",
    "  color:#eee !important; background:transparent !important;",
    "}",
    "html.tdlive-on .LNavCat { color:#fdd023 !important; }",
    "html.tdlive-on #ddmenuMem1 a, html.tdlive-on .menu-nav a, html.tdlive-on .logonav-hide a { color:#fdd023 !important; }",
    "html.tdlive-on .footer a, html.tdlive-on .foot { color:#ccc !important; }",
    "html.tdlive-on input[type=text], html.tdlive-on input[type=password], html.tdlive-on input[type=search],",
    "html.tdlive-on input[type=email], html.tdlive-on input[type=url], html.tdlive-on input.loginbox,",
    "html.tdlive-on textarea, html.tdlive-on select, html.tdlive-on .forum-search__input {",
    "  background:#1a1a1a !important; color:#fff !important; border:1px solid #555 !important;",
    "  caret-color:#fdd023;",
    "}",
    "html.tdlive-on input[type=submit], html.tdlive-on input[type=button], html.tdlive-on button,",
    "html.tdlive-on .login-button, html.tdlive-on .forum-search__submit {",
    "  background:#461d7c !important; color:#fdd023 !important; border:1px solid #2a1150 !important;",
    "}",
    "html.tdlive-on .inline-index-ad, html.tdlive-on .sponsor, html.tdlive-on .LNavSky, html.tdlive-on .LNavSky2,",
    "html.tdlive-on #lowlead, html.tdlive-on .lowLead, html.tdlive-on .editorial-card, html.tdlive-on #follow {",
    "  display:none !important;",
    "}",
    "html.tdlive-on .scoreboard-subject, html.tdlive-on .scoreboard-index, html.tdlive-on .srcdiv1, html.tdlive-on .srcdiv2 {",
    "  background:transparent !important; color:#fff !important;",
    "}",
    "html.tdlive-on .scoreteam, html.tdlive-on .scorescr, html.tdlive-on .scoreqtr, html.tdlive-on .scoretv,",
    "html.tdlive-on .scoretvdesktop, html.tdlive-on .score-rank, html.tdlive-on .mobiletv {",
    "  color:#fff !important;",
    "}",
    "html.tdlive-on .score-winner, html.tdlive-on .scoreteam.score-winner, html.tdlive-on .scorescr.score-winner {",
    "  color:#fdd023 !important; font-weight:700 !important;",
    "}",
    "html.tdlive-on .score-loser { color:#c8c8c8 !important; }",
    "html.tdlive-on .tdlive-pin { color:#fdd023; margin-right:6px; font-size:12px; vertical-align:middle; }",
    "html.tdlive-on .tdlive-badge {",
    "  display:inline-block; margin-left:8px; padding:1px 7px; border-radius:999px;",
    "  background:#fdd023; color:#000 !important; font-size:11px; font-weight:800; line-height:1.4;",
    "  vertical-align:middle; letter-spacing:0;",
    "}",
    "html.tdlive-on .tdlive-seen h2 a, html.tdlive-on .tdlive-seen .scoreboard-subject a { color:#8c8c8c !important; }",
    "html.tdlive-on .tdlive-votebar {",
    "  position:absolute; top:0; bottom:0; width:5px; pointer-events:none; z-index:3;",
    "}",
    "html.tdlive-on .tdlive-votebar-l { left:0; }",
    "html.tdlive-on .tdlive-votebar-r { right:0; }",
    "html.tdlive-on .tdlive-toolbar {",
    "  position:sticky; top:0; z-index:1000; display:flex; align-items:center; gap:10px; flex-wrap:wrap;",
    "  background:#0a0a0a !important; border-bottom:1px solid #333; padding:8px 14px; color:#fff !important;",
    "}",
    "html.tdlive-on .tdlive-toolbar-title { font-weight:700; color:#fff !important; font-size:14px; margin-right:auto; }",
    "html.tdlive-on .tdlive-status { color:#9a9a9a !important; font-size:12px; }",
    "html.tdlive-on .tdlive-btn {",
    "  appearance:none; border:0; cursor:pointer; font-weight:700; font-size:13px;",
    "  padding:6px 12px; border-radius:999px; color:#fff !important;",
    "}",
    "html.tdlive-on .tdlive-btn-live { background:#461d7c !important; color:#fff !important; }",
    "html.tdlive-on .tdlive-btn-live.is-on { background:#c41616 !important; }",
    "html.tdlive-on .tdlive-btn-live.is-on::before { content:''; display:inline-block; width:7px; height:7px; border-radius:50%;",
    "  background:#fff; margin-right:6px; box-shadow:0 0 0 0 rgba(255,255,255,.8); animation:tdlivePulse 1.4s infinite; }",
    "@keyframes tdlivePulse { 0% { box-shadow:0 0 0 0 rgba(255,255,255,.7); } 70% { box-shadow:0 0 0 8px rgba(255,255,255,0); } 100% { box-shadow:0 0 0 0 rgba(255,255,255,0); } }",
    "html.tdlive-on .tdlive-marker {",
    "  display:flex; align-items:center; gap:8px; padding:8px 14px 10px; background:#000 !important;",
    "}",
    "html.tdlive-on .tdlive-marker-line { flex:1; height:1px; background:rgba(253,208,35,.7); }",
    "html.tdlive-on .tdlive-marker-label {",
    "  color:#fdd023 !important; font-size:11px; font-weight:800; letter-spacing:.04em; white-space:nowrap;",
    "}",
    "html.tdlive-on .tdlive-newtoast {",
    "  position:fixed; bottom:20px; left:50%; transform:translateX(-50%); z-index:2000;",
    "  background:#fdd023; color:#000 !important; font-weight:800; font-size:13px;",
    "  padding:8px 14px; border-radius:999px; cursor:pointer; box-shadow:0 4px 16px rgba(0,0,0,.4);",
    "}",
    "html.tdlive-on span.tdlive-badge { color:#000 !important; background:#fdd023 !important; }",
    "html.tdlive-on a.mbsortsel, html.tdlive-on .mbsortsel {",
    "  background:#461d7c !important; color:#fdd023 !important; padding:1px 6px !important; border-radius:4px !important;",
    "}",
    "html.tdlive-on a.bread3, html.tdlive-on .bread3 { background:transparent !important; color:#fdd023 !important; }",
    "html.tdlive-on #overflow, html.tdlive-on .dd_1Col, html.tdlive-on .MenuL {",
    "  background:#111 !important; color:#fff !important; border:1px solid #333 !important;",
    "}",
    "html.tdlive-on #overflow a, html.tdlive-on .dd_1Col a, html.tdlive-on .MenuL a { color:#fdd023 !important; }",
    "html.tdlive-on .ad_center, html.tdlive-on [id^=\"div-gpt-ad\"], html.tdlive-on .leaderfull,",
    "html.tdlive-on .TOI_flex1, html.tdlive-on .TOI_box { display:none !important; }",
    "html.tdlive-on #main.Main, html.tdlive-on .Main, html.tdlive-on .body-content {",
    "  width:100% !important; max-width:none !important;",
    "}",
    "html.tdlive-on #forumcontent, html.tdlive-on #forumcontent.bodyR1, html.tdlive-on .bodyR1,",
    "html.tdlive-on .maincont, html.tdlive-on #mbind, html.tdlive-on #mbmt {",
    "  width:min(980px, calc(100% - 32px)) !important; max-width:980px !important;",
    "}",
    "html.tdlive-on #ContentL { display:none !important; }",
    "html.tdlive-on .index.indRow, html.tdlive-on .index.indRowAlt { position:relative !important; padding-left:22px !important; }",
    "html.tdlive-on .index .tdlive-pin { position:absolute !important; left:5px; top:10px; margin:0 !important; }",
    "html.tdlive-on #tdlive-injected { display:none !important; }",
  ].join("\n");

  function voteScore(up, down) {
    var total = up + down;
    if (total <= 0) return 0;
    var net = (up - down) / total;
    var confidence = 1 - Math.exp(-total / 8);
    return net * confidence;
  }

  function voteBarColor(up, down) {
    var s = voteScore(up, down);
    if (Math.abs(s) < 0.08) return "transparent";
    var c = s > 0 ? GREEN : RED;
    var a = Math.min(1, 0.12 + 0.95 * Math.abs(s));
    return "rgba(" + c.r + "," + c.g + "," + c.b + "," + a + ")";
  }

  function injectStyle() {
    if (!document.documentElement) return;
    if (document.getElementById("tdlive-style")) return;
    var style = document.createElement("style");
    style.id = "tdlive-style";
    style.textContent = CSS;
    (document.head || document.documentElement).appendChild(style);
  }

  function bootClass() {
    if (!document.documentElement) return false;
    document.documentElement.classList.add("tdlive-on");
    injectStyle();
    return true;
  }

  function loadPositions() {
    try {
      var raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return {};
      var v = JSON.parse(raw);
      return v && typeof v === "object" ? v : {};
    } catch (e) {
      return {};
    }
  }

  function savePositions(map) {
    try {
      var keys = Object.keys(map);
      if (keys.length > MAX_STORED) {
        keys.sort(function (a, b) {
          return (map[b].updated || 0) - (map[a].updated || 0);
        });
        var keep = {};
        keys.slice(0, MAX_STORED).forEach(function (k) { keep[k] = map[k]; });
        map = keep;
      }
      localStorage.setItem(STORAGE_KEY, JSON.stringify(map));
    } catch (e) { /* quota / private mode */ }
    return map;
  }

  var positions = loadPositions();

  function getPos(id) { return positions[id] || null; }

  function markSeen(threadId, postId, page, replyCount) {
    if (!threadId) return;
    var p = positions[threadId] || { lastPostId: postId || "", lastPage: page || 1, replyCount: 0, updated: 0 };
    var changed = !positions[threadId];
    if (postId && (parseInt(postId, 10) || 0) > (parseInt(p.lastPostId, 10) || 0)) {
      p.lastPostId = String(postId);
      if (page) p.lastPage = page;
      changed = true;
    }
    if (typeof replyCount === "number" && replyCount > (p.replyCount || 0)) {
      p.replyCount = replyCount;
      changed = true;
    }
    if (!changed) return;
    p.updated = Date.now();
    positions[threadId] = p;
    positions = savePositions(positions);
  }

  function parsePath(pathname) {
    var path = pathname || location.pathname;
    var thread = path.match(/^\/rant\/[^/]+\/[^/]+\/(\d+)\/(?:page-(\d+)\/?)?$/i);
    if (thread) {
      var base = path.replace(/page-\d+\/?$/, "");
      if (base.slice(-1) !== "/") base += "/";
      return {
        type: "thread",
        id: thread[1],
        page: parseInt(thread[2] || "1", 10),
        path: base
      };
    }
    // Boards: /rant/lsu-sports/ or /rant/lsu-sports/page-2/ or /rant/a/trending/
    var board = path.match(/^\/rant\/(?:a\/)?[^/]+\/(?:page-(\d+)\/?)?$/i);
    if (board) {
      return { type: "board", page: parseInt(board[1] || "1", 10), path: path };
    }
    return { type: "other", path: path };
  }

  function threadPageUrl(basePath, page) {
    var p = basePath;
    if (p.slice(-1) !== "/") p += "/";
    return p + (page <= 1 ? "" : "page-" + page + "/");
  }

  function postIdFromEl(el) {
    var p = el.querySelector && el.querySelector('.pText[id^="ptext_"]');
    if (!p) return null;
    return p.id.replace(/^ptext_/, "");
  }

  function postEls(root) {
    root = root || document;
    var nodes = root.querySelectorAll("div.maincont1.indRow, div.maincont1.indRowAlt");
    var out = [];
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      if (el.classList.contains("sponsor")) continue;
      if (el.closest && el.closest("#tdlive-injected")) continue;
      if (postIdFromEl(el)) out.push(el);
    }
    return out;
  }

  function votesFor(el, id) {
    var upEl = el.querySelector("#T_Up_p" + id) || document.getElementById("T_Up_p" + id);
    var downEl = el.querySelector("#T_Down_p" + id) || document.getElementById("T_Down_p" + id);
    var up = parseInt(upEl && upEl.textContent, 10);
    var down = parseInt(downEl && downEl.textContent, 10);
    return { up: isNaN(up) ? 0 : up, down: isNaN(down) ? 0 : down };
  }

  function enhancePost(el, isOp) {
    var id = postIdFromEl(el);
    if (!id) return id;
    if (isOp) el.classList.add("tdlive-post-op");
    el.classList.add("tdlive-post");
    var v = votesFor(el, id);
    var color = voteBarColor(v.up, v.down);
    var left = el.querySelector(".tdlive-votebar-l");
    var right = el.querySelector(".tdlive-votebar-r");
    if (!left) {
      left = document.createElement("div");
      left.className = "tdlive-votebar tdlive-votebar-l";
      left.setAttribute("aria-hidden", "true");
      el.insertBefore(left, el.firstChild);
    }
    if (!right) {
      right = document.createElement("div");
      right.className = "tdlive-votebar tdlive-votebar-r";
      right.setAttribute("aria-hidden", "true");
      el.appendChild(right);
    }
    left.style.background = color;
    right.style.background = color;
    el.dataset.tdlivePostId = id;
    return id;
  }

  function parsePageInfo(doc) {
    doc = doc || document;
    var text = doc.body ? doc.body.innerText : "";
    var m = text.match(/Page\s+(\d+)\s+of\s+(\d+)/i);
    if (m) return { page: parseInt(m[1], 10), total: parseInt(m[2], 10) };
    var max = 1;
    var links = doc.querySelectorAll('a.pg[href*="/page-"], a[href*="/page-"]');
    for (var i = 0; i < links.length; i++) {
      var mm = (links[i].getAttribute("href") || "").match(/\/page-(\d+)\//);
      if (mm) max = Math.max(max, parseInt(mm[1], 10));
    }
    var cur = parsePath((doc === document ? location.pathname : (doc.location && doc.location.pathname) || "")).page || 1;
    return { page: cur, total: Math.max(max, cur) };
  }

  function estimateReplyCount(page, totalPages, postsOnPage, onLastPage) {
    if (!onLastPage) return null;
    return Math.max(0, (totalPages - 1) * POSTS_PER_PAGE + postsOnPage - 1);
  }

  function rowThreadInfo(row) {
    var a = row.querySelector("h2 a[href]");
    if (!a) return null;
    var href = a.getAttribute("href") || "";
    var m = href.match(/\/(\d+)\/(?:page-\d+\/)?(?:#.*)?$/);
    if (!m) return null;
    var col3 = row.querySelector(".index_col3");
    var replies = 0;
    if (col3) {
      var rm = (col3.textContent || "").replace(/,/g, "").match(/(\d+)/);
      if (rm) replies = parseInt(rm[1], 10);
    }
    return { id: m[1], href: href, replies: replies, anchor: a, row: row };
  }

  function enhanceBoard() {
    var rows = document.querySelectorAll("div.index.indRow, div.index.indRowAlt");
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i];
      if (row.classList.contains("inline-index-ad")) continue;
      var info = rowThreadInfo(row);
      if (!info) continue;

      if ((row.innerHTML.indexOf("srcstick") !== -1 || row.innerHTML.indexOf("alt=\"sticky post\"") !== -1 ||
           row.querySelector(".scoreboard-subject") || row.querySelector(".picons.sticky")) &&
          !row.querySelector(".tdlive-pin")) {
        var pin = document.createElement("span");
        pin.className = "tdlive-pin";
        pin.setAttribute("aria-label", "Pinned");
        pin.textContent = "📌";
        var h2 = row.querySelector("h2");
        if (h2) h2.insertBefore(pin, h2.firstChild);
      }

      var pos = getPos(info.id);
      var existing = row.querySelector(".tdlive-badge");
      if (pos) {
        var n = Math.max(0, info.replies - (pos.replyCount || 0));
        if (n > 0) {
          if (!existing) {
            existing = document.createElement("span");
            existing.className = "tdlive-badge";
            if (info.anchor && info.anchor.parentNode) {
              info.anchor.parentNode.appendChild(existing);
            } else {
              row.appendChild(existing);
            }
          }
          existing.textContent = "+" + n;
        } else if (existing) {
          existing.remove();
        }
        if (n === 0) row.classList.add("tdlive-seen");
        else row.classList.remove("tdlive-seen");
      }

      (function (info) {
        if (info.anchor.dataset.tdliveBound) return;
        info.anchor.dataset.tdliveBound = "1";
        info.anchor.addEventListener("click", function () {
          // Record the list's reply count as of this visit so +N is accurate later.
          markSeen(info.id, null, null, info.replies);
        });
      })(info);
    }
  }

  function atBottom() {
    var slack = 80;
    return (window.innerHeight + window.scrollY) >= (document.documentElement.scrollHeight - slack);
  }

  function scrollToPost(id) {
    var el = document.getElementById("ptext_" + id);
    if (!el) {
      var wrap = document.querySelector('[data-tdlive-post-id="' + id + '"]');
      if (wrap) wrap.scrollIntoView({ block: "start" });
      return;
    }
    var post = el.closest(".tdlive-post") || el;
    post.scrollIntoView({ block: "start" });
  }

  function insertResumeMarker(lastPostId) {
    if (!lastPostId || document.getElementById("tdlive-resume-marker")) return;
    var posts = postEls();
    var after = null;
    var lastNum = parseInt(lastPostId, 10) || 0;
    for (var i = 0; i < posts.length; i++) {
      var id = postIdFromEl(posts[i]);
      if ((parseInt(id, 10) || 0) > lastNum) {
        after = posts[i];
        break;
      }
    }
    if (!after) return; // no newer posts on this page
    var marker = document.createElement("div");
    marker.id = "tdlive-resume-marker";
    marker.className = "tdlive-marker";
    marker.innerHTML = '<div class="tdlive-marker-line"></div><div class="tdlive-marker-label">NEW POSTS BELOW</div><div class="tdlive-marker-line"></div>';
    after.parentNode.insertBefore(marker, after);
  }

  var liveTimer = null;
  var liveOn = false;
  var lastLiveCheck = 0;
  var polling = false;
  var toolbarStatus = null;
  var toastEl = null;
  var pendingNew = 0;
  var wasAtBottom = true;

  function setStatus(text) {
    if (toolbarStatus) toolbarStatus.textContent = text || "";
  }

  function showToast(n) {
    if (n <= 0) {
      if (toastEl) toastEl.remove();
      toastEl = null;
      return;
    }
    if (!toastEl) {
      toastEl = document.createElement("div");
      toastEl.className = "tdlive-newtoast";
      toastEl.addEventListener("click", function () {
        var posts = postEls();
        if (posts.length) posts[posts.length - 1].scrollIntoView({ block: "end", behavior: "smooth" });
        showToast(0);
        pendingNew = 0;
      });
      document.body.appendChild(toastEl);
    }
    toastEl.textContent = n === 1 ? "1 new post" : n + " new posts";
  }

  function updateVoteBars() {
    var posts = postEls();
    for (var i = 0; i < posts.length; i++) enhancePost(posts[i], i === 0 && parsePath().page === 1);
  }

  function appendPostsFromDoc(doc, pageInfo) {
    var incoming = postEls(doc);
    var have = {};
    var existing = postEls();
    existing.forEach(function (el) { have[postIdFromEl(el)] = true; });
    var last = existing[existing.length - 1];
    var added = [];
    for (var i = 0; i < incoming.length; i++) {
      var src = incoming[i];
      var id = postIdFromEl(src);
      if (!id || have[id]) continue;
      var node = document.importNode(src, true);
      node.querySelectorAll("script").forEach(function (s) { s.remove(); });
      if (last && last.parentNode) {
        last.parentNode.insertBefore(node, last.nextSibling);
      } else {
        var host = document.getElementById("mbmt") || document.getElementById("forumcontent");
        if (host) host.appendChild(node);
        else continue;
      }
      enhancePost(node, false);
      have[id] = true;
      added.push(id);
      last = node;
      existing.push(node);
    }
    return added;
  }

  function fetchDoc(url) {
    return fetch(url, { credentials: "same-origin", cache: "no-store" }).then(function (res) {
      if (!res.ok) throw new Error("HTTP " + res.status);
      return res.text();
    }).then(function (html) {
      return new DOMParser().parseFromString(html, "text/html");
    });
  }

  function poll(page) {
    if (polling) return Promise.resolve(0);
    polling = true;
    var info = parsePath();
    var pageInfo = parsePageInfo(document);
    var targetPage = page || pageInfo.total || info.page;
    var url = threadPageUrl(info.path, targetPage);
    return fetchDoc(url).then(function (doc) {
      lastLiveCheck = Date.now();
      var docInfo = parsePageInfo(doc);
      var added = [];
      if (targetPage === info.page || targetPage === (pageInfo.total || info.page)) {
        added = appendPostsFromDoc(doc, docInfo);
      }
      // If the live site grew a new page, fetch that too.
      if (docInfo.total > targetPage) {
        return fetchDoc(threadPageUrl(info.path, docInfo.total)).then(function (doc2) {
          var more = appendPostsFromDoc(doc2, parsePageInfo(doc2));
          return added.concat(more);
        });
      }
      return added;
    }).then(function (added) {
      updateVoteBars();
      if (added && added.length) {
        var lastId = added[added.length - 1];
        var pos = getPos(info.id);
        var newCount = (pos && pos.replyCount || 0) + added.length;
        markSeen(info.id, lastId, pageInfo.total || info.page, newCount);
        if (wasAtBottom || atBottom()) {
          var posts = postEls();
          if (posts.length) posts[posts.length - 1].scrollIntoView({ block: "end", behavior: "smooth" });
          pendingNew = 0;
          showToast(0);
        } else {
          pendingNew += added.length;
          showToast(pendingNew);
        }
      }
      if (liveOn) {
        var t = new Date(lastLiveCheck);
        var hh = t.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit", second: "2-digit" });
        setStatus("Live · checking every 5s · last check " + hh);
      }
      return (added && added.length) || 0;
    }).catch(function (err) {
      setStatus("Live · couldn't refresh");
      return 0;
    }).then(function (n) {
      polling = false;
      return n;
    });
  }

  function stopLive() {
    liveOn = false;
    try { localStorage.setItem(LIVE_PREF_KEY, "0"); } catch (e) {}
    if (liveTimer) { clearInterval(liveTimer); liveTimer = null; }
    var btn = document.getElementById("tdlive-live-btn");
    if (btn) {
      btn.classList.remove("is-on");
      btn.textContent = "Go Live";
      btn.setAttribute("aria-pressed", "false");
    }
    setStatus("");
  }

  function startLive(opts) {
    opts = opts || {};
    var info = parsePath();
    var pageInfo = parsePageInfo(document);
    if (!opts.skipJump && pageInfo.total > info.page) {
      try { sessionStorage.setItem(WANT_LIVE_KEY, info.id); } catch (e) {}
      try { localStorage.setItem(LIVE_PREF_KEY, "1"); } catch (e) {}
      location.href = threadPageUrl(info.path, pageInfo.total);
      return;
    }
    liveOn = true;
    try { localStorage.setItem(LIVE_PREF_KEY, "1"); } catch (e) {}
    var btn = document.getElementById("tdlive-live-btn");
    if (btn) {
      btn.classList.add("is-on");
      btn.textContent = "Live";
      btn.setAttribute("aria-pressed", "true");
    }
    setStatus("Live · checking every 5s");
    if (liveTimer) clearInterval(liveTimer);
    poll();
    liveTimer = setInterval(function () { poll(); }, POLL_MS);
  }

  function threadTitle() {
    var titleEl = document.querySelector("h1.SubjectDisplay");
    var raw = titleEl ? titleEl.textContent : (document.title || "");
    raw = raw.replace(/^\s*re:\s*/i, "").replace(/\s*[-|]\s*TigerDroppings.*$/i, "").trim();
    return raw || "Thread";
  }

  function addToolbar(title) {
    if (document.getElementById("tdlive-toolbar")) return;
    var bar = document.createElement("div");
    bar.id = "tdlive-toolbar";
    bar.className = "tdlive-toolbar";
    var t = document.createElement("div");
    t.className = "tdlive-toolbar-title";
    t.textContent = title || "TD Live";
    var status = document.createElement("div");
    status.className = "tdlive-status";
    status.id = "tdlive-status";
    toolbarStatus = status;
    var btn = document.createElement("button");
    btn.type = "button";
    btn.id = "tdlive-live-btn";
    btn.className = "tdlive-btn tdlive-btn-live";
    btn.textContent = "Go Live";
    btn.setAttribute("aria-pressed", "false");
    btn.addEventListener("click", function () {
      if (liveOn) stopLive();
      else startLive();
    });
    bar.appendChild(t);
    bar.appendChild(status);
    bar.appendChild(btn);
    var host = document.getElementById("forumcontent") || document.getElementById("mbmt") || document.body;
    var paging = host.querySelector && host.querySelector(".Paging");
    if (paging && paging.parentNode) paging.parentNode.insertBefore(bar, paging.nextSibling);
    else host.insertBefore(bar, host.firstChild);
  }

  function trackReads(threadId, page, totalReplies) {
    var posts = postEls();
    if (!("IntersectionObserver" in window)) {
      if (posts.length) markSeen(threadId, postIdFromEl(posts[posts.length - 1]), page, totalReplies);
      return;
    }
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (!en.isIntersecting) return;
        var id = postIdFromEl(en.target);
        if (id) markSeen(threadId, id, page, totalReplies);
      });
    }, { threshold: 0.4 });
    posts.forEach(function (el) { io.observe(el); });
    window.addEventListener("scroll", function () { wasAtBottom = atBottom(); }, { passive: true });
  }

  function enhanceThread() {
    var info = parsePath();
    var posts = postEls();
    var pageInfo = parsePageInfo(document);
    var title = threadTitle();
    addToolbar(title);

    for (var i = 0; i < posts.length; i++) {
      enhancePost(posts[i], i === 0 && info.page === 1);
    }

    var replyCount = estimateReplyCount(info.page, pageInfo.total, posts.length, info.page >= pageInfo.total);
    var pos = getPos(info.id);
    if (replyCount == null && pos && typeof pos.replyCount === "number") replyCount = pos.replyCount;
    if (typeof replyCount === "number") markSeen(info.id, null, info.page, replyCount);

    var wantLive = false;
    try { wantLive = sessionStorage.getItem(WANT_LIVE_KEY) === info.id; sessionStorage.removeItem(WANT_LIVE_KEY); } catch (e) {}

    // Resume: if we landed on page 1 with a stored later page and no explicit hash, jump there.
    var hash = location.hash || "";
    var explicit = hash && hash !== "#top" && hash !== "#tdlive-toolbar";
    if (!wantLive && !explicit && pos && pos.lastPage && pos.lastPage > info.page && info.page === 1) {
      location.replace(threadPageUrl(info.path, pos.lastPage) + (pos.lastPostId ? "#ptext_" + pos.lastPostId : ""));
      return;
    }

    if (pos && pos.lastPostId) {
      insertResumeMarker(pos.lastPostId);
      var target = pos.lastPostId;
      // Scroll after layout. If a native hash already points at the post, the browser may have scrolled.
      function jumpToResume() {
        var m = document.getElementById("tdlive-resume-marker");
        if (m) {
          var y = m.getBoundingClientRect().top + window.scrollY - 56;
          window.scrollTo(0, Math.max(0, y));
          return true;
        }
        scrollToPost(target);
        return false;
      }
      requestAnimationFrame(function () {
        setTimeout(jumpToResume, 50);
        setTimeout(jumpToResume, 300);
      });
    }

    trackReads(info.id, info.page, replyCount);

    if (wantLive) startLive({ skipJump: true });
  }

  function widenLayout() {
    ["forumcontent", "mbind", "mbmt"].forEach(function (id) {
      var el = document.getElementById(id);
      if (!el) return;
      el.style.setProperty("width", "min(980px, calc(100% - 32px))", "important");
      el.style.setProperty("max-width", "980px", "important");
    });
    var main = document.getElementById("main") || document.querySelector(".Main, .body-content");
    if (main) {
      main.style.setProperty("width", "100%", "important");
      main.style.setProperty("max-width", "none", "important");
    }
  }

  function init() {
    bootClass();
    positions = loadPositions();
    widenLayout();
    var page = parsePath();
    if (page.type === "board") enhanceBoard();
    else if (page.type === "thread") enhanceThread();
  }

  function start() {
    bootClass();
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", init);
    } else {
      init();
    }
  }

  if (document.documentElement) {
    start();
  } else {
    var started = false;
    function kick() {
      if (started || !document.documentElement) return;
      started = true;
      start();
    }
    document.addEventListener("readystatechange", kick);
    document.addEventListener("DOMContentLoaded", kick);
    var n = 0;
    var iv = setInterval(function () {
      kick();
      if (started || ++n > 200) clearInterval(iv);
    }, 5);
  }
})();
