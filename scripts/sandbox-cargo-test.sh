#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -eq 0 ]]; then
  echo "usage: $0 [cargo test arguments...]" >&2
  exit 2
fi

repo_root="$(git rev-parse --show-toplevel)"
image="codex-sandbox-smoke:rust-1.95.0"

docker build \
  --file "$repo_root/.devcontainer/Dockerfile.sandbox-smoke" \
  --tag "$image" \
  "$repo_root/.devcontainer"

# Keep the host checkout read-only. The sandbox tests need a writable cwd, so
# copy the workspace into tmpfs. Cargo's caches and build artifacts use named
# volumes so repeated runs reuse downloads without writing into the host.
# Bubblewrap needs nested namespaces; capabilities remain dropped.
docker run --rm \
  --cap-drop=ALL \
  --security-opt seccomp=unconfined \
  --mount "type=bind,src=$repo_root/codex-rs,dst=/source,readonly" \
  --tmpfs /codex-workspace:rw,exec,size=2g,uid=1000,gid=1000,mode=0755 \
  --mount type=volume,src=codex-sandbox-cargo-registry-v2,dst=/home/codex/.cargo/registry \
  --mount type=volume,src=codex-sandbox-cargo-git-v2,dst=/home/codex/.cargo/git \
  --mount type=volume,src=codex-sandbox-target,dst=/codex-target \
  --workdir /codex-workspace \
  --env CARGO_TARGET_DIR=/codex-target \
  --env CARGO_BUILD_JOBS=1 \
  --env CARGO_INCREMENTAL=0 \
  --env CARGO_PROFILE_DEV_DEBUG=0 \
  --env CARGO_PROFILE_TEST_DEBUG=0 \
  --env 'RUSTFLAGS=-C link-arg=-Wl,--no-keep-memory' \
  --env RUST_MIN_STACK=8388608 \
  "$image" \
  sh -c 'mkdir -p /codex-workspace/codex-rs && tar -C /source --exclude=target -cf - . | tar -C /codex-workspace/codex-rs -xf - && cd /codex-workspace/codex-rs && host="$(rustc -vV | sed -n "s/^host: //p")" && linker_dir="$(rustc --print sysroot)/lib/rustlib/$host/bin/gcc-ld" && export PATH="$linker_dir:$PATH" && linker=/tmp/codex-clang-lld && printf "%s\n" "#!/usr/bin/env python3" "import os, sys" "args = [arg for arg in sys.argv[1:] if arg != \"-Wl,--no-keep-memory\"]" "os.execvp(\"clang\", [\"clang\", \"-fuse-ld=lld\", \"-Wl,--threads=1\", *args])" > "$linker" && chmod +x "$linker" && target_env="$(printf "%s" "$host" | tr "[:lower:]-" "[:upper:]_")" && export "CARGO_TARGET_${target_env}_LINKER=$linker" && cargo test "$@"' sh "$@"
