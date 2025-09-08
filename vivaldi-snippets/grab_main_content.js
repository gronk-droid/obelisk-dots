// grabs the main content tags of a page and copies them to the clipboard
// add with quick commands in vivaldi settings with Command 1 as Open Link in Current Tab

javascript: function copy(e) {
  var elements = document.querySelectorAll("h1, h2, h3, h4, h5, h6, p");
  var text = Array.prototype.map
    .call(elements, function (el) {
      var tag = el.tagName.toLowerCase();
      var content = el.innerText.trim();
      if (content.length === 0) return "";
      return tag.toUpperCase() + ": " + content;
    })
    .filter(Boolean)
    .join("\n\n");
  e.clipboardData.setData("text/plain", text);
  e.preventDefault();
}
document.addEventListener("copy", copy);
document.execCommand("copy");
document.removeEventListener("copy", copy);
history.replaceState({}, "", location.href);
