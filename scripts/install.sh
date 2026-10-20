#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
skill_root="${script_dir:h}"
source_cli="${1:-$skill_root/bin/macos-universal/videohero}"
destination="${2:-$HOME/.local/bin/videohero}"
verify_script="$script_dir/verify.sh"

if [[ "$source_cli" != /* || "$destination" != /* ]]; then
  print -u2 "Source and destination must be absolute paths"
  exit 2
fi

"$verify_script" --require-checksum "$source_cli"

if [[ -d "$destination" ]]; then
  print -u2 "Destination is a directory and was not changed: $destination"
  exit 4
fi
if [[ -e "$destination" || -L "$destination" ]]; then
  if ! "$verify_script" "${destination:A}" >/dev/null 2>&1; then
    print -u2 "Destination contains another or unverifiable tool and was not changed: $destination"
    exit 4
  fi
fi

destination_dir="${destination:h}"
/bin/mkdir -p "$destination_dir"
temporary="$destination_dir/.videohero-install-${$}.tmp"
trap '/bin/rm -f "$temporary"' EXIT
/usr/bin/ditto "$source_cli" "$temporary"
/bin/chmod 755 "$temporary"
"$verify_script" "$temporary" >/dev/null
/bin/mv -f "$temporary" "$destination"
trap - EXIT

"$verify_script" "$destination" >/dev/null
print "Installed VideoHero CLI: $destination"
print "Add $destination_dir to PATH if your agent does not already inherit it."
