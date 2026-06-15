# FUSE correctness model: shadow-inode phasing + caller-owned creations

Three invariants govern how `rp-fuse` interacts with the Linux kernel's inode cache and the container's user model. They were not visible at design time; each surfaced as a real bug during a single `npm ci` run and was fixed in commits `a8fb1ed`, `f3d4874`, and `109d210`. This ADR records the model so the next maintainer doesn't have to re-derive it from symptoms.

## Invariant 1 — Backing and shadow inodes are namespace-disjoint

`rp-fuse` mounts two `LoopbackRoot` trees side-by-side (`/var/lib/rp/backing` for passthrough, `/var/lib/rp/shadow` for shadowed paths). go-fuse's stock `idFromStat` formula reduces to `Ino = st.Ino` whenever the underlying inode lives on the same device as the root — which is always true for a single-FS backing. Both trees therefore produce the same `StableAttr.Ino` for any pair of files that happen to share `st.Ino`, and the kernel inode cache aliases them. Real repro: a backing directory at inode 159 (`projects/common/src/cache/strategies`) aliased with a shadow file at inode 159 (`node_modules/@tsconfig/node10`) after `npm install`; `ls -l strategies/` returned ENOENT even though `stat` succeeded.

Fix: every shadow-tree node carries a high-bit phase XOR'd into its `StableAttr.Ino` (`shadowPhase = 1<<63`). Backing-tree nodes keep their natural Ino. The two spaces are now disjoint regardless of how low the underlying inode numbers go. The phase is applied at every shadow-side node-registration point — `shadowChild`, `ShadowNode.Lookup`, `ShadowNode.{Create,Mkdir,Symlink,Mknod}`, and the `Readdir` merge step. Adding a new shadow-create path without phasing reintroduces aliasing.

We rejected (a) disabling kernel caching entirely (kills performance for the FUSE's main hot path — directory walks during agent indexing) and (b) using go-fuse's bridge-level uniqification (not exposed in v2.5.1). Phase-XOR is cheap, transparent to the kernel, and reversible.

## Invariant 2 — Shadow-created files are owned by the FUSE caller

`rp-fuse` runs as root (PID 1 = init, with CAP_SYS_ADMIN required for the mount). When a non-root caller — e.g. `coder` (uid 1001 on devcontainer-derived images) — creates a file through FUSE, the syscall executes inside the FUSE driver process and the resulting file in the shadow store is owned by **root**. The caller then tries to `fchmod` the fd they hold, and the Linux kernel rejects it with EPERM **before the request reaches FUSE**: man `fchmod` — *"The effective UID does not match the owner of the file, and the process does not have CAP_FOWNER."*

This breaks anything that opens-then-fchmods: GNU `install`, tar with `--preserve-permissions`, `cp --preserve=mode`. Path-based `chmod foo` works fine because it goes through FUSE Setattr (the driver chmods as root); only direct-fd ops fail. The symptom is misleading — basic shell chmod works in tests, so the trap is invisible until a complex install fails.

Fix: every shadow-side create operation (`HostNode.Create`, `HostNode.Mkdir/Symlink/Mknod`'s shadow branch, `ShadowNode.Create/Mkdir/Symlink/Mknod`, and every intermediate dir made by `ensureShadowParent`) chowns the newly-created node to the caller's uid/gid via `fuse.FromContext(ctx).Caller`. Caller information is plumbed by go-fuse on every request and reflects the actual triggering user.

We rejected `setfsuid`-per-request because it's racy across goroutines (a global thread-local change), and `default_permissions` because it would shift permission enforcement to the kernel — which doesn't know about the shadow store and would refuse all kinds of legitimate operations. Post-create chown is the smallest change that restores the user-owns-their-files contract.

Security note: `/var/lib/rp/shadow` itself remains 0700 root-owned, so the caller cannot bypass FUSE to reach the store directly. Only files created via FUSE flip ownership.

## Invariant 3 — Privileged image users are refused, at both build and run time

ADR-0005 establishes the shadow boundary by giving the container user no `sudo` and no capabilities. A user with sudo in `/etc/sudoers` can re-enter the FUSE process namespace and bypass the shadow store. Devcontainer images routinely ship a `node` user with sudo — the most common case where the invariant is violated without anyone noticing.

The overlay build already enforces both `uid != 0` and `! grep -rqE "(^|[[:space:]])${user}([[:space:]]|$)" /etc/sudoers /etc/sudoers.d/`. We add a runtime re-check in `rp-init.sh` so the invariant holds even if a future change to the build path slips a privileged user through, and so that `rp start` on a stopped container re-asserts the property after `rp` itself has been upgraded.

Build-time check is the primary guard. Runtime is belt-and-braces. Both fail loudly with a message naming the offending user.

## Implications for testing

Each invariant has property tests under `just test-integration`:

1. Inode phase: Go unit tests on `idFromStat` / `idFromShadowStat`; shell test with a deliberate inode collision.
2. Caller ownership: shell test running as non-root, creating files in shadow, asserting `stat.uid == caller.uid`.
3. Privileged user: shell test attempting `rp create` against a base image whose configured user is in sudoers; assert build fails with the expected message.

Removing or weakening any of these tests means a future regression of that exact class will land silently — these bugs are all silent failures (wrong file returned, EPERM, sudo working invisibly). Tests are the only catch.
