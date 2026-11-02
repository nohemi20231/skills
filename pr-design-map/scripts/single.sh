#!/usr/bin/env bash
# Builds one self-contained page from a built out dir: style.css, data.js and app.js inline, fonts from Google Fonts.
# Use it when the viewer cannot load an artifact's sub-files (Safari). Usage: single.sh <out-dir>  ->  <out-dir>/single.html
set -euo pipefail
out=$(cd "$1" && pwd)
perl -e '
  my ($out) = @ARGV; local $/;
  sub slurp { open my $f, "<", $_[0] or die "$_[0]: $!"; my $s = <$f>; close $f; $s }
  my $html = slurp("$out/index.html"); my $css = slurp("$out/style.css");
  my $data = slurp("$out/data.js");    my $app = slurp("$out/app.js");
  $css =~ s/^\@font-face\{[^\n]*\n//mg;
  my $fonts = qq{<link rel="preconnect" href="https://fonts.googleapis.com">\n<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>\n<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Lexend:wght\@400;700&family=JetBrains+Mono:wght\@400;700&display=swap">};
  $html =~ s{<link rel="stylesheet" href="style.css">}{$fonts\n<style>\n$css</style>} or die "no stylesheet link";
  $html =~ s{<script src="data.js"></script>}{<script>\n$data</script>} or die "no data.js tag";
  $html =~ s{<script src="app.js"></script>}{<script>\n$app</script>} or die "no app.js tag";
  open my $o, ">", "$out/single.html" or die; print $o $html; close $o;
' "$out"
echo "wrote $out/single.html ($(wc -c < "$out/single.html") bytes)"
