# Shadow as security boundary via drop-sudo + namespace hide

The shadow mechanism is promoted from "ergonomic isolation" to a real security boundary against in-container code. Concretely:

- **`coder` user loses passwordless sudo.** The Dockerfile no longer grants `coder ALL=(ALL) NOPASSWD:ALL`.
- **`rp-init.sh` hides the host bind from the container's mount namespace.** The host workspace is bind-mounted at `/workspace`; before `rp-fuse` starts, init captures an fd on that bind, then overlays a tmpfs and `rp-fuse` on top of `/workspace`. The user-visible filesystem at `/workspace` is the FUSE layer; the raw bind is reachable only via the captured fd (`/proc/self/fd/N`), held by `rp-fuse`. If `rp-fuse` fails or exits, the tmpfs layer remains as a fail-closed backstop (empty, not the raw bind). See ADR-0010 for the mount layout.
- **`/var/lib/rp/` is `0700 root:root`.** `coder` cannot traverse it, so symlinks crafted to escape into the shadow store get EACCES.

Verified by spike (2026-06-13): a `coder` exec'd process has `CapInh = CapPrm = CapEff = 0`. `umount` on the FUSE / tmpfs / bind stack returns EPERM. The raw host bind is not visible to the user.

Trade-off accepted:

- **Lose**: `apt-get`, `pip install -g`, system config changes from inside the container. The in-container `CLAUDE.md` advice to "install anything" is removed; new system packages must be baked into the image via `rp rebuild`.
- **Gain**: Claude (or any in-container process) genuinely cannot read host content outside the `.ccrshadow` ruleset, even with intent.

The earlier broader path to harden was rejected (rewriting go-fuse loopback to `openat`-based access, fork maintenance, fragility). The chosen path is simpler: rely on POSIX perms + capability-less user, plus a tmpfs cover. Container restart is required to take effect; the boundary is enforced from PID 1 onwards.

If Apple Container later exposes per-exec capability controls or per-process mount namespaces, that opens further hardening options without requiring sudo to be dropped.
