# fix-permissions-hoffman2

Fixes group ownership and group permissions on everything **you** own under a
shared project directory on Hoffman2, so the rest of the lab can read and write it.

For every file or directory you own under the given path it:

- sets the group to the lab group (`chgrp`)
- gives the group read/write on files, plus execute where the owner has execute
- gives the group read/write/execute on directories, plus the setgid bit so new
  files created inside inherit the lab group

It only changes what actually needs changing, prints each change, and ends with a
summary. Files owned by other people can't be changed by you; the summary lists
who owns them so they can run the script themselves.

## Install (once, on your Hoffman2 account)

```bash
git clone https://github.com/clarefmccann/fix-permissions-hoffman2.git ~/fix-permissions-hoffman2
chmod +x ~/fix-permissions-hoffman2/fix-permissions-group-wide.sh
```

To get the latest version later:

```bash
cd ~/fix-permissions-hoffman2 && git pull
```

## Usage

```bash
~/fix-permissions-hoffman2/fix-permissions-group-wide.sh [-n] [-v] <base_dir> <group>
```

| Option | What it does |
|--------|--------------|
| `-n`   | Dry run: list what would change, change nothing |
| `-v`   | Verbose: print a progress line every 15 seconds so you can see it's still working |

Always try a dry run first:

```bash
~/fix-permissions-hoffman2/fix-permissions-group-wide.sh -n -v /u/project/silvers/data silvers
```

Then run it for real:

```bash
~/fix-permissions-hoffman2/fix-permissions-group-wide.sh -v /u/project/silvers/data silvers
```

To save the list of changes to a file while still seeing progress on screen:

```bash
~/fix-permissions-hoffman2/fix-permissions-group-wide.sh -v /u/project/silvers/data silvers > changes.log
```

## Notes

- **Large directories take a while.** On a big tree the scan can run for many
  minutes. Use `-v` to see that it's still moving. To change how often it reports,
  set `HEARTBEAT_SECS`, e.g. `HEARTBEAT_SECS=60`.
- **Very large trees:** consider running it in an interactive session
  (`qrsh`) or a batch job rather than on a login node.
- **Symlinks are skipped**, so the script never changes anything outside the
  directory you give it.
- **Unreadable directories** (ones you can't enter) are skipped and listed in the
  summary with their owner, who needs to run the script on them.
- You must be a member of the group you name; check with `id -nG`.
