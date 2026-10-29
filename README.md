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
git -C ~/fix-permissions-hoffman2 config core.fileMode false
```

To get the latest version later:

```bash
cd ~/fix-permissions-hoffman2 && git pull
```

## Usage

```bash
bash ~/fix-permissions-hoffman2/fix-permissions-group-wide.sh [-n] [-v] [-x PATH]... [-X FILE] <base_dir> <group>
```

| Option    | What it does |
|-----------|--------------|
| `-n`      | Dry run: list what would change, change nothing |
| `-v`      | Verbose: print a progress line every 15 seconds so you can see it's still working |
| `-x PATH` | Leave `PATH` (and everything under it) untouched. Repeat for several paths. Relative paths are relative to `<base_dir>`; quoted wildcards work (`-x '*/scratch'` skips every `scratch` directory at any depth) |
| `-X FILE` | Read more paths to leave untouched from `FILE`, one per line (`#` comments allowed) |

Paths listed in `excludes.txt` (next to the script) are always skipped, so the
lab's "do not touch" list applies to everyone.

## Running it on Hoffman2 (Slurm)

Don't run it on a login node: a large scan is CPU and I/O heavy and may be
killed there. Start an interactive session on a compute node first.

**1. (Optional) start `tmux`** on the login node, so the session survives a
dropped connection. If you get disconnected, log back in to the same login node
and run `tmux attach`.

```bash
tmux
```

**2. Start an interactive session:**

```bash
srun --time=8:00:00 --mem=1G --pty bash -l
```

- **Always include `--mem=1G`.** Without it, Hoffman2 gives your session *all*
  the memory of the node, which blocks other jobs from using it. The script only
  needs a little.
- `--time` can be up to `24:00:00`. The session (and the script) is stopped when
  the time runs out, so ask for plenty on a big tree.
- If you belong to more than one Slurm account, add `-A pi_<PI's user name>`
  (e.g. `-A pi_silvers`). With only one account it's picked automatically.
- When your prompt changes from `login…` to a compute node name, you're in. If
  it sits waiting, the request is queued for a node; `h2 why-pending <JOB_ID>`
  explains why.

**3. Do a dry run first:**

```bash
bash ~/fix-permissions-hoffman2/fix-permissions-group-wide.sh -n -v /u/project/silvers/data silvers
```

**4. Then run it for real:**

```bash
bash ~/fix-permissions-hoffman2/fix-permissions-group-wide.sh -v /u/project/silvers/data silvers
```

To save the list of changes to a file while still seeing progress on screen
(progress goes to stderr, changes to stdout):

```bash
bash ~/fix-permissions-hoffman2/fix-permissions-group-wide.sh -v /u/project/silvers/data silvers > logs/changes.log
```

**5. Type `exit`** when it's done to end the session and release the node.

### As a batch job instead (optional)

If you'd rather submit it and walk away, **don't `sbatch` the script itself**.
Slurm runs a copy of the submitted script from a spool directory, so it can't
find `excludes.txt` and the lab's "do not touch" paths would not be skipped.


```bash
sbatch fixperms.sbatch      # prints the job ID
squeue --me                 # is it pending (PD) or running (R)?
tail -f logs/progress/fixperms-<JOB_ID>.progress   # live progress
cat logs/changes/fixperms-<JOB_ID>.changes       # changes + summary when done
scancel <JOB_ID>            # stop it (ONLY IF NOTICING ERROR)
```

The separate `--error` file keeps the progress lines out of the list of changes
(Slurm puts both in one file by default). Output files are written to the
directory you ran `sbatch` from; use full paths in `#SBATCH` lines if you want
them elsewhere (environment variables like `$SCRATCH` are not expanded there).

## Notes

- **Large directories take a while.** On a big tree the scan can run for many
  minutes or hours. Use `-v` to see that it's still moving. To change how often
  it reports, set `HEARTBEAT_SECS`, e.g. `HEARTBEAT_SECS=60`.
- **If it's stopped part-way** (time limit, disconnect), just run it again. It
  only changes what still needs fixing, but you only get the summary from a
  complete run.
- **Symlinks are skipped**, so the script never changes anything outside the
  directory you give it.
- **Unreadable directories** (ones you can't enter) are skipped and listed in the
  summary with their owner, who needs to run the script on them.
- You must be a member of the group you name; check with `id -nG`.
