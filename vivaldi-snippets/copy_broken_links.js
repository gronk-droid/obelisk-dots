// run directly from command palette in vivaldi
// add with quick commands in vivaldi settings with Command 1 as Open Link in Current Tab

javascript: (function () {
  async function run() {
    var anchors = Array.from(document.querySelectorAll("a[href]"));
    var results = [];
    for (const a of anchors) {
      try {
        const res = await fetch(a.href, { method: "HEAD", mode: "no-cors" });
        if (!res.ok) {
          results.push("BROKEN: " + a.href + " (" + res.status + ")");
        }
      } catch (err) {
        results.push("ERROR: " + a.href);
      }
    }
    if (results.length === 0) {
      alert("No broken links detected on this page 🎉");
    } else {
      alert("Found " + results.length + " broken/problem links. See console.");
      console.log("Broken/Problem Links:", results);
    }
  }
  run();
})();
