# Opt-in sudo stripping for image-default users

Some base images — most notably devcontainer images like `mcr.microsoft.com/devcontainers/javascript-node:22` — ship a conventional user (`node`) with passwordless sudo. ADR-0005's shadow boundary requires the container user to have *no* path to root, so the overlay refuses to use that user out of the box (`! grep sudoers <user>` check fails the build).

Two ways out:

1. Set `user: coder` and let the overlay create a fresh non-privileged user. Loses the image's preexisting home (nvm install, npm config, shell rc) — anything keyed to `/home/node/` is gone.
2. Have the overlay strip the user's sudo grant during build and continue to use the image's conventional user. Keeps the image's preexisting setup but mutates the image's intended security posture.

We pick **opt-in (2) via `.rp/config.yaml`'s `strip_sudo: true` flag**, default false (refuse-and-recommend-coder).

## Why opt-in, not always-strip

Silently mutating an image's security posture is surprising. A user who set `user: node` because they wanted node's preexisting environment may not realise rp also altered the image's sudoers; if they later run a workflow that depends on node having sudo (legitimate inside the container — apt-install in a dev box, switching identities for tests), it fails in a confusing way. Forcing the explicit flag makes the trade legible: *"yes, I know this image's default user has sudo, and I'm telling rp to remove it."*

## Why not always-refuse

The user mistake we're protecting against is "I want to use node, but I don't know it has sudo." With an explicit error message naming the sudoers file and pointing at `strip_sudo`, the next step is clear. Pure refusal forces every devcontainer user into the `user: coder` path, which loses a lot of practical convenience for no extra security (the boundary holds the same way either route).

## What the strip removes

The overlay emits four idempotent steps when `strip_sudo: true`:

1. `rm -f /etc/sudoers.d/<user>` — drops a per-user include file (where devcontainer images typically grant the NOPASSWD line).
2. `sed -i '/^<user>\s/d' /etc/sudoers` — drops any direct user grant in the main sudoers file.
3. `sed -i` inside every `/etc/sudoers.d/*` to drop user-grant lines plus `%sudo`/`%wheel` group grants (covers indirect grants).
4. `gpasswd -d <user> sudo` + `gpasswd -d <user> wheel` — removes the user from the sudo / wheel groups so even an inherited group grant fails.

After these, the **existing** `! grep -rqE "(^|\s)<user>(\s|$)" /etc/sudoers /etc/sudoers.d/` check still runs. If the strip missed a path (a sudo grant through a NIS map, a non-standard sudoers include, a PAM module that doesn't consult sudoers), the build fails with the existing refusal message and the user has a clear signal. `strip_sudo` is best-effort; the post-strip check is the safety net.

## Implications

- `strip_sudo: true` is image-specific knowledge: it presumes the image's `<user>` is the devcontainer-shipped user and that the standard four locations cover the grant. New image families (Bottles, rocky-like images) may need additional strip steps; the post-strip check fails loudly if so.
- A workspace that wants legitimate sudo for some niche workflow loses it post-strip. The escape hatch is `user: coder` + manually replicate the image's user-specific config, or use a different image.
- `rp lint` could WARN when `strip_sudo: true` is set so the user is reminded the image is being mutated. Deferred until requested.
- Runtime check in `rp-init.sh` (ADR-0008 invariant 3) re-validates the user is not in sudoers at start time. It catches any post-build sudoers edit (e.g. someone exec'd in as root and added node back to sudoers) — strip + runtime-check together close the loop.
