#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build-local}"
PREFIX="${PREFIX:-/usr}"
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  SUDO="${SUDO:-}"
else
  SUDO="${SUDO:-sudo}"
fi

if [[ "$BUILD_DIR" != /* ]]; then
  BUILD_DIR="$ROOT_DIR/$BUILD_DIR"
fi

meson_opts=(
  "--prefix=$PREFIX"
  "-Dappend_libdir_mangohud=false"
  "-Dwith_xnvctrl=disabled"
)

usage() {
  cat <<EOF
Usage: ./build-local.sh <command> [meson options]

Commands:
  deps       Install build dependencies for Ubuntu/Fedora
  configure Configure Meson using this local checkout
  build      Configure if needed, then build
  install    Build, then install with sudo
  clean      Remove the local build directory

Environment:
  BUILD_DIR  Build directory (default: ./build-local)
  PREFIX     Install prefix (default: /usr)
  SUDO       Privilege command (default: sudo)

Example:
  ./build-local.sh deps
  ./build-local.sh build
  ./build-local.sh install
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

distro_id() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    echo "${ID_LIKE:-} ${ID:-}"
  fi
}

install_deps() {
  local ids
  ids="$(distro_id)"

  if [[ "$ids" == *ubuntu* || "$ids" == *debian* ]]; then
    $SUDO apt update
    $SUDO apt install -y \
      build-essential git cmake ninja-build meson pkg-config \
      glslang-tools libx11-dev libwayland-dev libdbus-1-dev \
      libxkbcommon-dev libgl-dev python3-mako
    return
  fi

  if [[ "$ids" == *fedora* || "$ids" == *rhel* ]]; then
    $SUDO dnf install -y \
      gcc gcc-c++ git cmake ninja-build meson pkgconf-pkg-config \
      glslang libX11-devel wayland-devel dbus-devel \
      libxkbcommon-devel mesa-libGL-devel python3-mako
    return
  fi

  echo "Unsupported distro. This helper currently supports Ubuntu/Debian and Fedora/RHEL-like systems." >&2
  exit 1
}

configure() {
  need_cmd meson
  cd "$ROOT_DIR"

  if [[ -f "$BUILD_DIR/build.ninja" ]]; then
    meson setup "$BUILD_DIR" --reconfigure "${meson_opts[@]}" "$@"
  else
    meson setup "$BUILD_DIR" "${meson_opts[@]}" "$@"
  fi
}

build() {
  need_cmd ninja
  if [[ ! -f "$BUILD_DIR/build.ninja" ]]; then
    configure "$@"
  fi

  ninja -C "$BUILD_DIR"
}

install_local() {
  build "$@"
  $SUDO ninja -C "$BUILD_DIR" install
  $SUDO sed -i 's/\r$//' "$PREFIX/bin/mangohud"
  $SUDO chmod 755 "$PREFIX/bin/mangohud"
  if [[ -f "$PREFIX/bin/mangoplot" ]]; then
    $SUDO sed -i 's/\r$//' "$PREFIX/bin/mangoplot"
    $SUDO chmod 755 "$PREFIX/bin/mangoplot"
  fi
}

clean() {
  case "$BUILD_DIR" in
    "$ROOT_DIR"/*) rm -rf "$BUILD_DIR" ;;
    *) echo "Refusing to remove BUILD_DIR outside the repo: $BUILD_DIR" >&2; exit 1 ;;
  esac
}

cmd="${1:-}"
if [[ -z "$cmd" ]]; then
  usage
  exit 1
fi
shift

case "$cmd" in
  deps) install_deps ;;
  configure) configure "$@" ;;
  build) build "$@" ;;
  install) install_local "$@" ;;
  clean) clean ;;
  -h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac
