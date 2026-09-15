#!/bin/bash
set -euo pipefail

RESOURCE="$1"
[ -f "$RESOURCE" ] || {
  echo "FAIL: Required Chrome extension ID resource is missing: $RESOURCE" >&2
  exit 1
}

/usr/bin/perl -MJSON::PP -e '
  local $/;
  open my $file, "<", $ARGV[0]
    or die "FAIL: Cannot read Chrome extension ID resource.\n";
  my $ids = eval { decode_json(<$file>) };
  if ($@ || ref($ids) ne "ARRAY" || !@$ids) {
    die "FAIL: Chrome extension IDs must be a nonempty JSON array.\n";
  }
  for my $id (@$ids) {
    unless (defined($id) && !ref($id) && $id =~ /\A[a-p]{32}\z/) {
      die "FAIL: Each Chrome extension ID must contain exactly 32 lowercase letters from a to p.\n";
    }
  }
' "$RESOURCE"
