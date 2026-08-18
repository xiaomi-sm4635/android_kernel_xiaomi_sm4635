#!/bin/bash
set -e

source .github/workflows/config.sh

echo "[+] Target Device: ${DEVICE_CODENAME}"
export PATH="${TC_DIR}/bin:${PATH}"

# Prepare output directories
rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}" "${OUT_DIR}/dist" "${OUT_DIR}/modules"

echo "[+] Generating base defconfig (${DEFCONFIG})..."
make O="${OUT_DIR}" ARCH=${ARCH} ${DEFCONFIG}

echo "[+] Merging vendor config (${VENDOR_CONFIG})..."
if [ -f "arch/arm64/configs/${VENDOR_CONFIG}" ]; then
    ./scripts/kconfig/merge_config.sh -m -O "${OUT_DIR}" "${OUT_DIR}/.config" "arch/arm64/configs/${VENDOR_CONFIG}"
fi

echo "[+] Resolving missing default configs..."
make O="${OUT_DIR}" ARCH=${ARCH} olddefconfig

# Complete build parameters
BUILD_FLAGS=(
    -j${JOBS}
    O="${OUT_DIR}"
    ARCH=${ARCH}
    CC=${CC}
    LD=${LD}
    LLVM=${USE_LLVM}
    HOSTCFLAGS="-O2 -Wno-error -Wno-incompatible-pointer-types-discards-qualifiers"
    HOSTCXXFLAGS="-O2 -Wno-error"
    KCFLAGS="-Wno-error=frame-larger-than"
)

echo "[+] Compiling full kernel tree (Image, Modules, DTBs)..."
make "${BUILD_FLAGS[@]}" all 2>&1 | tee "${ROOT_DIR}/build.log"

echo "[+] Installing kernel modules..."
make "${BUILD_FLAGS[@]}" INSTALL_MOD_PATH="${OUT_DIR}/modules" modules_install

echo "[+] Packaging build outputs into dist/ folder..."

# Copy kernel image variants
for img in Image Image.gz Image.gz-dtb; do
    if [ -f "${OUT_DIR}/arch/arm64/boot/${img}" ]; then
        cp "${OUT_DIR}/arch/arm64/boot/${img}" "${OUT_DIR}/dist/"
    fi
done

# Copy DTBs and DTBOs
find "${OUT_DIR}/arch/arm64/boot/dts" -type f \( -name "*.dtb" -o -name "*.dtbo" \) -exec cp {} "${OUT_DIR}/dist/" \; 2>/dev/null || true

# Archive compiled modules
cd "${OUT_DIR}/modules"
tar -czf "${OUT_DIR}/dist/modules.tar.gz" .
cd "${ROOT_DIR}"

echo "[SUCCESS] Complete build finished!"
echo "[+] All artifacts collected in: ${OUT_DIR}/dist/"
