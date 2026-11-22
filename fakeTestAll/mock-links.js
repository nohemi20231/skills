// fakeTestAll only. The mocked pull request is not on GitHub, so each link the design map built for it is pointed
// at the local stand-in pages that mock-github.sh wrote to ../mock-github. The templates are not changed:
// build-pages.sh adds this script to the built pages under out/ and fills in @GH@ and @SESSION@.
(function () {
  var gh = '@GH@', session = '@SESSION@', base = '../mock-github/';
  function local(url) {
    var m;
    if (url === session) return base + 'session.html';
    if (url.indexOf(gh) !== 0) return null;
    url = url.slice(gh.length);
    if ((m = /^pull\/(\d+)\/files(#.*)?$/.exec(url))) return base + 'pull-' + m[1] + '-files.html' + (m[2] || '');
    if ((m = /^pull\/(\d+)$/.exec(url))) return base + 'pull-' + m[1] + '.html';
    if ((m = /^blob\/(.+)$/.exec(url))) return base + 'blob/' + m[1] + '.html';
    return null;
  }
  function fix() {
    document.querySelectorAll('a[href^="https://"]').forEach(function (a) {
      var to = local(a.getAttribute('href'));
      if (to) a.setAttribute('href', to);
    });
  }
  fix();
  // links inside folds and panels are rendered later
  new MutationObserver(fix).observe(document.documentElement, { childList: true, subtree: true });
})();
