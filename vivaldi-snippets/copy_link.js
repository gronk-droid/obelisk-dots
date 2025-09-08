// same as copy_link_md.js but without markdown
// add with quick commands in vivaldi settings with Command 1 as Open Link in Current Tab

javascript: function copy(e) {
  e.clipboardData.setData("text/plain", location.href);
  e.preventDefault();
}
document.addEventListener("copy", copy);
document.execCommand("copy");
document.removeEventListener("copy", copy);
history.replaceState({}, "", location.href);
