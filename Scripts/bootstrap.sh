#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
REV=e5f5a022fe96fc4dc2ee35c19f733a50df807abe
CMAKE="${CMAKE:-cmake}"
if ! command -v "$CMAKE" >/dev/null 2>&1; then
  if [ -x "$ROOT/.build/tools/cmake/data/bin/cmake" ]; then
    CMAKE="$ROOT/.build/tools/cmake/data/bin/cmake"
  else
    echo '需要 CMake 3.15+。可运行 python3 -m pip install --target .build/tools cmake==3.31.6' >&2
    exit 1
  fi
fi
mkdir -p .build/deps .build/native/include .build/native/lib
if [ ! -d .build/deps/libultrahdr/.git ]; then
  git clone https://github.com/google/libultrahdr.git .build/deps/libultrahdr
fi
git -C .build/deps/libultrahdr checkout --detach "$REV"
"$CMAKE" -S .build/deps/libultrahdr -B .build/deps/uhdr-build \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DBUILD_SHARED_LIBS=OFF -DUHDR_BUILD_DEPS=ON -DUHDR_BUILD_EXAMPLES=OFF \
  -DUHDR_ENABLE_HEIF=OFF -DUHDR_WRITE_XMP=ON -DUHDR_WRITE_ISO=ON
"$CMAKE" --build .build/deps/uhdr-build --parallel 4
cp .build/deps/libultrahdr/ultrahdr_api.h .build/native/include/
cp .build/deps/uhdr-build/libuhdr.a .build/native/lib/
cp .build/deps/uhdr-build/turbojpeg/src/turbojpeg-build/libjpeg.a .build/native/lib/
mkdir -p .build/native/licenses
cp .build/deps/libultrahdr/LICENSE-* .build/native/licenses/
cp .build/deps/libultrahdr/third_party/turbojpeg/LICENSE.md .build/native/licenses/libjpeg-turbo-LICENSE.md
cp .build/deps/libultrahdr/third_party/turbojpeg/README.ijg .build/native/licenses/libjpeg-turbo-README.ijg
