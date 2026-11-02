# SPDX-License-Identifier: MIT
{ pkgs }:
pkgs.runCommand "kiss-community-32ed193" { } ''
  mkdir -p $out/bin
  cp ${
    pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/kiss-community/kiss/32ed1933ac8ccc5816cfdcc51769fe756232fc68/kiss";
      hash = "sha256-mHTiCQKQNyFW9YQMa3tS0hAePa4p4isEKDHRxhY2M+Q=";
    }
  } $out/bin/kiss
  chmod 755 $out/bin/kiss
  patchShebangs $out/bin/kiss
''
