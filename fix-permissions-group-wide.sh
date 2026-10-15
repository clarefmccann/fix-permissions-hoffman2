#!/bin/bash
# Fix group ownership + group permissions on everything YOU own under a directory.
# Only touches files that actually need changing, prints each change it makes,
# and ends with a summary so that "no changes" is never a mystery.
#
# usage: fix-permissions-group-wide.sh [-n] [-v] <base_dir> <group>
#   -n   dry run: list what would be changed, change nothing
#   -v   verbose: print a progress heartbeat on stderr every 15 seconds
#        (elapsed time + the directory currently being scanned)
#        set HEARTBEAT_SECS to change the interval
#
# example: fix-permissions-group-wide.sh -v /u/project/silvers/data silvers
#          fix-permissions-group-wide.sh -nv /u/project/silvers/data silvers

set -u

usage() { echo "usage: $0 [-n] [-v] <base_dir> <group>" >&2; exit 1; }

dry_run=0
verbose=0
while getopts "nv" opt; do
    case "$opt" in
        n) dry_run=1 ;;
        v) verbose=1 ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

# Progress messages go to stderr so stdout stays a clean list of changes.
vlog() {
    if [ "$verbose" -eq 1 ]; then
        echo "# [$(date '+%H:%M:%S')] $*" >&2
    fi
}

base_dir="${1:-}"
target_group="${2:-}"

if [ -z "$base_dir" ] || [ -z "$target_group" ]; then
    usage
fi
if [ ! -d "$base_dir" ]; then
    echo "error: $base_dir is not a directory" >&2
    exit 1
fi

# Resolve symlinks in the starting path. find does not follow a symlink given as
# its starting point, so without this a symlinked base_dir silently matches nothing.
given_dir="$base_dir"
base_dir=$(realpath "$base_dir") || exit 1

# Ask the system who we are: the USER variable can be unset or stale in batch jobs.
me=$(id -un)

if ! id -nG | tr ' ' '\n' | grep -qx "$target_group"; then
    echo "error: $me is not a member of group '$target_group'" >&2
    exit 1
fi

vlog "user $me, group '$target_group', base $base_dir$([ "$dry_run" -eq 1 ] && echo ' (dry run)')"

# find writes one line per item of interest here; we summarise it at the end.
tally=$(mktemp) || exit 1
trap 'rm -f "$tally"' EXIT

# Tests for "needs fixing".
mine=( -user "$me" )
wrong_group=( ! -group "$target_group" )
bad_dir=( -type d ! -perm -2070 )                       # missing any of g+rwx or setgid
bad_file=( ! -type d \( ! -perm -g+rw -o \( -perm /111 ! -perm -g+x \) \) )
needs_fix=( \( "${wrong_group[@]}" -o "${bad_dir[@]}" -o "${bad_file[@]}" \) )

if [ "$dry_run" -eq 1 ]; then
    echo "# dry run -- nothing will be changed"
    actions=( \( "${mine[@]}" "${needs_fix[@]}" -printf '%M %u:%g %p\n' \) )
else
    # -c makes chgrp/chmod report only the files they actually change.
    actions=(
        \( "${mine[@]}" "${wrong_group[@]}" -exec chgrp -c "$target_group" {} + \) ,
        \( "${mine[@]}" "${bad_dir[@]}"     -exec chmod -c g+rwxs {} + \) ,
        \( "${mine[@]}" "${bad_file[@]}"    -exec chmod -c g+rwX {} + \)
    )
fi

# Verbose: a background heartbeat that periodically reports elapsed time and
# where find currently is. The location is read from the directory find has
# open (/proc/<pid>/fd), so it is live even when output is going to a log file.
heartbeat() {
    local pid where sp=""
    # On stop, take the pending sleep down with us (quietly, no orphan left behind).
    trap 'kill "$sp" 2>/dev/null; exit 0' TERM
    while :; do
        sleep "${HEARTBEAT_SECS:-15}" & sp=$!
        wait "$sp"
        pid=$(pgrep -P "$$" -x find | head -n 1)
        where=""
        if [ -n "$pid" ]; then
            # deepest directory under base_dir that find has open
            where=$(for fd in /proc/"$pid"/fd/*; do readlink "$fd"; done 2>/dev/null \
                    | grep -F "$base_dir" | awk '{ print length($0) "\t" $0 }' \
                    | sort -rn | head -n 1 | cut -f2-)
        fi
        vlog "still working ($((SECONDS / 60))m $((SECONDS % 60))s elapsed)${where:+, now in $where}"
    done
}

hb_pid=""
stop_heartbeat() {
    if [ -n "$hb_pid" ]; then
        kill "$hb_pid" 2>/dev/null
        wait "$hb_pid" 2>/dev/null
        hb_pid=""
    fi
}
trap 'stop_heartbeat; rm -f "$tally"' EXIT
trap 'exit 130' INT TERM

if [ "$verbose" -eq 1 ]; then
    heartbeat &
    hb_pid=$!
fi

vlog "walking the tree (this can take a while on a large or parallel filesystem)"

# Single traversal (one walk of the tree is much kinder to a parallel filesystem).
# Symlinks are skipped: chmod/chgrp would follow them and could modify targets
# outside base_dir. Directories we cannot read are noted and pruned, not entered.
find "$base_dir" ! -type l \
    \( -type d ! -readable -fprintf "$tally" 'denied %p\n' -prune \) -o \( \
       \( "${mine[@]}"                    -fprintf "$tally" 'mine\n' \) , \
       \( "${mine[@]}"   "${needs_fix[@]}" -fprintf "$tally" 'fix\n' \) , \
       \( ! "${mine[@]}" "${needs_fix[@]}" -fprintf "$tally" 'other %u\n' \) , \
       "${actions[@]}" \
    \)

stop_heartbeat
vlog "tree walk finished after ${SECONDS}s; summarising"

# ---- summary ---------------------------------------------------------------
n_mine=$(grep -c '^mine$' "$tally")
n_fix=$(grep -c '^fix$' "$tally")
n_other=$(grep -c '^other ' "$tally")
[ "$dry_run" -eq 1 ] && verb="need fixing" || verb="needed fixing"

echo "# --- summary ---"
if [ "$given_dir" != "$base_dir" ]; then
    echo "# scanned $base_dir (resolved from $given_dir)"
else
    echo "# scanned $base_dir"
fi
if [ "$n_mine" -eq 0 ]; then
    echo "# nothing here is owned by $me, so there was nothing this script could change"
elif [ "$n_fix" -eq 0 ]; then
    echo "# $n_mine items owned by $me: all already have group '$target_group' and correct permissions"
else
    echo "# $n_mine items owned by $me: $n_fix $verb"
fi
if [ "$n_other" -gt 0 ]; then
    echo "# $n_other items owned by OTHER users need fixing; only their owner can do that:"
    grep '^other ' "$tally" | cut -d' ' -f2 | sort | uniq -c | sort -rn | sed 's/^/#   /'
fi

# Directories we could not read (no group r/x). Skipped; nothing beneath them was checked.
n_denied=$(grep -c '^denied ' "$tally")
if [ "$n_denied" -gt 0 ]; then
    echo "# $n_denied unreadable directories were skipped, so nothing inside them was checked."
    echo "# Their owners need to run this script (or chmod g+rwxs) on them:"
    sed -n 's/^denied //p' "$tally" | while IFS= read -r d; do
        printf '#   %-12s %s\n' "$(stat -c %U "$d" 2>/dev/null || echo '?')" "$d"
    done
fi

vlog "done in ${SECONDS}s"
