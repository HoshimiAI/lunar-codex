#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
image="codex-sandbox-smoke:rust-1.95.0"

docker build \
  --file "$repo_root/.devcontainer/Dockerfile.sandbox-smoke" \
  --tag "$image" \
  "$repo_root/.devcontainer"

# The repository is the writable workspace, while the rest of the host stays
# outside the container. Cargo and Codex state persist in named volumes.
docker run --rm -it \
  --cap-drop=ALL \
  --security-opt seccomp=unconfined \
  --mount "type=bind,src=$repo_root,dst=/workspace" \
  --volume codex-sandbox-codex-home:/home/codex/.codex \
  --mount type=volume,src=codex-sandbox-cargo-registry-v2,dst=/home/codex/.cargo/registry \
  --mount type=volume,src=codex-sandbox-cargo-git-v2,dst=/home/codex/.cargo/git \
  --mount type=volume,src=codex-sandbox-target,dst=/codex-target \
  --workdir /workspace/codex-rs \
  --env CODEX_HOME=/home/codex/.codex \
  --env CARGO_TARGET_DIR=/codex-target \
  --env CARGO_BUILD_JOBS=1 \
  --env CARGO_INCREMENTAL=0 \
  --env CARGO_PROFILE_DEV_DEBUG=0 \
  --env CARGO_PROFILE_TEST_DEBUG=0 \
  --env 'RUSTFLAGS=-C link-arg=-Wl,--no-keep-memory' \
  --env RUST_MIN_STACK=8388608 \
  --env OPENAI_API_KEY \
  "$image" \
  sh -c 'rm -f /home/codex/.codex/.volume-init && host="$(rustc -vV | sed -n "s/^host: //p")" && linker_dir="$(rustc --print sysroot)/lib/rustlib/$host/bin/gcc-ld" && export PATH="$linker_dir:$PATH" && linker=/tmp/codex-clang-lld && printf "%s\n" "#!/usr/bin/env python3" "import os, sys" "args = [arg for arg in sys.argv[1:] if arg != \"-Wl,--no-keep-memory\"]" "os.execvp(\"clang\", [\"clang\", \"-fuse-ld=lld\", \"-Wl,--threads=1\", *args])" > "$linker" && chmod +x "$linker" && target_env="$(printf "%s" "$host" | tr "[:lower:]-" "[:upper:]_")" && export "CARGO_TARGET_${target_env}_LINKER=$linker" && exec cargo run -p codex-cli --bin codex -- --no-daemon --sandbox workspace-write --ask-for-approval on-request "$@"' sh "$@"
