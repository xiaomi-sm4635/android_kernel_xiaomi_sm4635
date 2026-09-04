#!/bin/bash
#
# Compile script for Xiaomi SM4635 (warm/pitti) kernel, dts and modules
# Adapted from Xiaomi 8450 (vauxite) script by Adithya R. - original at
# https://raw.githubusercontent.com/pa-gr/android_kernel_xiaomi_sm8450/refs/heads/vauxite/build.sh
# Adapted for xiaomi-sm4635 (warm) - pitti platform, SM4635 SoC
# Kernel: android_kernel_xiaomi_warm (fork of LineageOS android_kernel_qcom_sm8650)
# Modules: sm4635-modules (android_kernel_sm4635-modules) - ../sm4635-modules
# Devicetrees: sm4635-devicetrees (android_kernel_xiaomi_sm4635-devicetrees) - ../sm4635-devicetrees
# Device codename: warm, platform: pitti
#

SECONDS=0
KP_ROOT="$(realpath ../.. 2>/dev/null || realpath ../../)"
# Try to find clang - original expects prebuilts-master/clang-r510928, but warm/pitti may use newer
# Search order: r510928 (AOSPA), r530567, r563880, any clang-*, fallback to system clang
TC_CANDIDATES=(
    "$KP_ROOT/prebuilts-master/clang/host/linux-x86/clang-r510928"
    "$KP_ROOT/prebuilts/clang/host/linux-x86/clang-r530567"
    "$KP_ROOT/prebuilts/clang/host/linux-x86/clang-r547379"
    "$KP_ROOT/prebuilts/clang/host/linux-x86/clang-r563880"
)
TC_DIR=""
for cand in "${TC_CANDIDATES[@]}"; do
    if [ -d "$cand" ]; then TC_DIR="$cand"; break; fi
done
# fallback: pick latest clang* in prebuilts-master if exists
if [ -z "$TC_DIR" ] && [ -d "$KP_ROOT/prebuilts-master/clang/host/linux-x86" ]; then
    TC_DIR="$(ls -d $KP_ROOT/prebuilts-master/clang/host/linux-x86/clang-* 2>/dev/null | sort -V | tail -n1)"
fi
if [ -z "$TC_DIR" ] && [ -d "$KP_ROOT/prebuilts/clang/host/linux-x86" ]; then
    TC_DIR="$(ls -d $KP_ROOT/prebuilts/clang/host/linux-x86/clang-* 2>/dev/null | sort -V | tail -n1)"
fi

PREBUILTS_DIR="$KP_ROOT/prebuilts/kernel-build-tools/linux-x86"
if [ ! -d "$PREBUILTS_DIR" ]; then
    # also check alternative location in AOSP
    for alt in "$KP_ROOT/prebuilts/build-tools/linux-x86" "$KP_ROOT/build/kernel/kleaf" ; do
        [ -d "$alt" ] && PREBUILTS_DIR="$alt" && break
    done
fi

BRANCH="$(git branch --show-current 2>/dev/null || echo warm)"
# warm uses short names: sm4635-modules and sm4635-devicetrees
# sibling to kernel at /home/yume/sm4635-* (symlink to android_kernel_* )
# Keep fallback to long names if short not exists
MODULES_REPO="sm4635-modules"
DT_REPO="sm4635-devicetrees"
# fallback check - if short name not exists, try long names
if [ ! -d "../$MODULES_REPO" ] && [ -d "../android_kernel_sm4635-modules" ]; then
    MODULES_REPO="android_kernel_sm4635-modules"
fi
if [ ! -d "../$DT_REPO" ] && [ -d "../android_kernel_xiaomi_sm4635-devicetrees" ]; then
    DT_REPO="android_kernel_xiaomi_sm4635-devicetrees"
fi
# also support devicetrees short name without xiaomi prefix
if [ ! -d "../$DT_REPO" ] && [ -d "../sm4635-devicetree" ]; then
    DT_REPO="sm4635-devicetree"
fi

DO_CLEAN=false
NO_LTO=false
ONLY_CONFIG=false
ONLY_KERNEL=false
ONLY_DTB=false
ONLY_MODULES=false
TARGET="warm"
DTB_WILDCARD="pitti"
DTBO_WILDCARD="warm-sm4635-overlay"

while [ $# -gt 0 ]; do
    case "$1" in
        -c | --clean) DO_CLEAN=true ;;
        -n | --no-lto) NO_LTO=true ;;
        -o | --only-config) ONLY_CONFIG=true ;;
        -k | --only-kernel) ONLY_KERNEL=true ;;
        -d | --only-dtb) ONLY_DTB=true ;;
        -m | --only-modules) ONLY_MODULES=true ;;
        *) TARGET="$1" ;;
    esac
    shift
done

# Handle TARGET mapping - warm is default, but support pitti as alias
case "$TARGET" in
    "warm" | "pitti" )
        DTB_WILDCARD="pitti"
        DTBO_WILDCARD="warm-sm4635-overlay"
        # Use warm for config selection even if TARGET=pitti
        CFG_TARGET="warm"
        ;;
    "marble" )
        DTB_WILDCARD="ukee"
        DTBO_WILDCARD="marble-sm7475-pm8008-overlay"
        CFG_TARGET="marble"
        ;;
    "cupid" )
        DTB_WILDCARD="waipio"
        DTBO_WILDCARD="cupid-sm8450-pm8008-overlay"
        CFG_TARGET="cupid"
        ;;
    *)
        echo "Unknown target '$TARGET', using warm defaults (pitti + warm overlay)"
        DTB_WILDCARD="pitti"
        DTBO_WILDCARD="warm-sm4635-overlay"
        CFG_TARGET="warm"
        ;;
esac
# For config merging, use CFG_TARGET
if [ "$CFG_TARGET" != "warm" ]; then
    # keep original behavior for other targets if borrowed
    TARGET_CFG="$CFG_TARGET"
else
    TARGET_CFG="warm"
fi

# .build.rc handling - now optional. If SRC_ROOT defined, copy artifacts to device kernel folder
# If not, just build and keep in out/ (user said they will do build)
SRC_ROOT=""
if [ -f .build.rc ]; then
    source .build.rc
fi

if [ -n "$SRC_ROOT" ]; then
    KERNEL_DIR="$SRC_ROOT/device/xiaomi/$TARGET-kernel"
    if [ ! -d "$KERNEL_DIR" ]; then
        echo "Warning: $KERNEL_DIR does not exist, will not copy. Build output stays in out/"
        KERNEL_COPY_TO="out/dist"
        DTB_COPY_TO="out/dist/dtbs"
        DTBO_COPY_TO="out/dist/dtbo.img"
        VBOOT_DIR="out/dist/vendor_ramdisk"
        VDLKM_DIR="out/dist/vendor_dlkm"
        COPY_ENABLED=false
    else
        KERNEL_COPY_TO="$KERNEL_DIR"
        DTB_COPY_TO="$KERNEL_DIR/dtbs"
        DTBO_COPY_TO="$DTB_COPY_TO/dtbo.img"
        VBOOT_DIR="$KERNEL_DIR/vendor_ramdisk"
        VDLKM_DIR="$KERNEL_DIR/vendor_dlkm"
        COPY_ENABLED=true
    fi
else
    echo "Note: .build.rc not found or SRC_ROOT empty - building standalone, output in out/"
    echo "Create .build.rc with SRC_ROOT=<path/to/aospa> to enable auto-copy to device/xiaomi/warm-kernel"
    KERNEL_COPY_TO="out/dist"
    DTB_COPY_TO="out/dist/dtbs"
    DTBO_COPY_TO="out/dist/dtbo.img"
    VBOOT_DIR="out/dist/vendor_ramdisk"
    VDLKM_DIR="out/dist/vendor_dlkm"
    COPY_ENABLED=false
fi

# For warm/pitti, DEFCONFIG remains gki_defconfig, merge pitti + warm fragments
# Original waipio + xiaomi + debugfs -> for warm we use pitti + warm
# debugfs.config does not exist for warm, so we skip if missing
DEFCONFIG="gki_defconfig"
# Build list dynamically, only include existing configs
DEFCONFIGS=""
for cfg in "vendor/pitti_GKI.config" "vendor/warm_GKI.config" "vendor/debugfs.config" "vendor/pitti_debug.config"; do
    if [ -f "arch/arm64/configs/$cfg" ]; then
        DEFCONFIGS="$DEFCONFIGS $cfg"
    fi
done
# If warm_GKI not found fallback to pitti only
if [ -z "$DEFCONFIGS" ]; then
    DEFCONFIGS="vendor/pitti_GKI.config"
fi
# Also handle vendor/${TARGET}_GKI.config if exists (for generic)
if [ -f "arch/arm64/configs/vendor/${TARGET_CFG}_GKI.config" ] && [[ "$DEFCONFIGS" != *"${TARGET_CFG}_GKI"* ]]; then
    DEFCONFIGS="$DEFCONFIGS vendor/${TARGET_CFG}_GKI.config"
fi

# Modules source - sibling repo qcom/opensource
MODULES_SRC="../$MODULES_REPO/qcom/opensource"
# For warm/pitti, modules to build separately - based on device's TARGET_KERNEL_EXT_MODULES + common qcom modules
# Device lists: securemsm, audio, synx, camera, dsp, eva, graphics, bt, spu, mm-sys ubwcp
# Add display, mmrm, video, wlan, dataipa etc for completeness - skip if missing at build time
MODULES="audio-kernel \
camera-kernel \
display-drivers/msm \
mm-sys-kernel/ubwcp \
securemsm-kernel \
synx-kernel \
dsp-kernel \
eva-kernel \
graphics-kernel \
bt-kernel \
spu-kernel \
mmrm-driver \
video-driver \
wlan/qcacld-3.0 \
dataipa/drivers/platform/msm \
datarmnet/core \
datarmnet-ext/aps \
datarmnet-ext/offload \
datarmnet-ext/shs \
datarmnet-ext/perf \
datarmnet-ext/perf_tether \
datarmnet-ext/sch \
datarmnet-ext/wlan \
touch-drivers \
fingerprint \
mm-drivers/sync_fence \
mm-drivers/msm_ext_display \
mm-drivers/hw_fence \
wlan/platform"

##
## Helper functions
##

echo_i() { echo -e "\n\033[1;36m==> $1\033[0m\n"; }

echo_w() { echo -e "\033[1;33m $1\033[0m"; }

echo_e() { echo -e "\n\033[1;31m $1\033[0m\n"; }

get_trees_rev() {
    kernel_rev="$(git rev-parse HEAD 2>/dev/null | cut -c1-10)"
    [[ -n "$(git --no-optional-locks status -uno --porcelain 2>/dev/null)" ]] && kernel_rev+="+"

    modules_rev="$(git -C ../$MODULES_REPO rev-parse HEAD 2>/dev/null | cut -c1-8)"
    [[ -n "$(git -C ../$MODULES_REPO --no-optional-locks status -uno --porcelain 2>/dev/null)" ]] && modules_rev+="+"

    dt_rev="$(git -C ../$DT_REPO rev-parse HEAD 2>/dev/null | cut -c1-8)"
    [[ -n "$(git -C ../$DT_REPO --no-optional-locks status -uno --porcelain 2>/dev/null)" ]] && dt_rev+="+"

    echo "-${kernel_rev}-m${modules_rev}-d${dt_rev}"
}

m() {
    # If PREBUILTS_DIR missing dtc, fall back to system dtc
    DTC_ARGS=""
    if [ -n "$PREBUILTS_DIR" ] && [ -x "$PREBUILTS_DIR/bin/dtc" ]; then
        DTC_ARGS="DTC_EXT=$PREBUILTS_DIR/bin/dtc DTC_OVERLAY_TEST_EXT=$PREBUILTS_DIR/bin/ufdt_apply_overlay"
    fi
    make -j$(nproc --all) O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 \
        $DTC_ARGS \
        TARGET_PRODUCT=$TARGET $@ || exit $?
}

build_kernel() {
    echo_i "Building kernel image..."
    m Image
    mkdir -p "$(dirname "$KERNEL_COPY_TO")"
    if [ -d "$KERNEL_COPY_TO" ]; then
        cp out/arch/arm64/boot/Image "$KERNEL_COPY_TO/"
        echo_i "Copied kernel Image to $KERNEL_COPY_TO/"
    else
        mkdir -p "$(dirname "$KERNEL_COPY_TO")"
        cp out/arch/arm64/boot/Image "$KERNEL_COPY_TO"
        echo_i "Copied kernel Image to $KERNEL_COPY_TO"
    fi
    # Also copy to out/dist for standalone
    mkdir -p out/dist
    cp out/arch/arm64/boot/Image out/dist/ 2>/dev/null || true
}

build_modules() {
    echo_i "Building kernel modules..."
    m modules
    rm -rf out/modules out/*.ko
    m INSTALL_MOD_PATH=modules INSTALL_MOD_STRIP=1 modules_install
    modules_out="out/modules/lib/modules/$(ls -t out/modules/lib/modules/ 2>/dev/null | head -n1)"

    # Handle KernelSU if present - optional, don't fail if missing
    if [ -n "$modules_out" ] && [ -d "$modules_out" ]; then
        ksu_path="$(find "$modules_out" -name 'kernelsu.ko' -print -quit 2>/dev/null)"
        if [ -n "$ksu_path" ]; then
            mv "$ksu_path" out/ 2>/dev/null || true
            echo_i "Copied kernelsu.ko to out/"
        else
            echo_w "kernelsu.ko not found (expected if KSU not enabled)"
        fi
    fi

    echo_i "Building techpack modules..."
    for module in $MODULES; do
        if [ ! -d "$MODULES_SRC/$module" ]; then
            echo_w "Skipping $module - not found at $MODULES_SRC/$module"
            continue
        fi
        if [ ! -f "$MODULES_SRC/$module/Kbuild" ] && [ ! -f "$MODULES_SRC/$module/Makefile" ]; then
            echo_w "Skipping $module - no Kbuild/Makefile at $MODULES_SRC/$module"
            continue
        fi
        echo -e "\nBuilding $module..."
        # Use raw make for techpack modules to allow graceful failure (m() has || exit)
        DTC_ARGS=""
        if [ -n "$PREBUILTS_DIR" ] && [ -x "$PREBUILTS_DIR/bin/dtc" ]; then
            DTC_ARGS="DTC_EXT=$PREBUILTS_DIR/bin/dtc DTC_OVERLAY_TEST_EXT=$PREBUILTS_DIR/bin/ufdt_apply_overlay"
        fi
        if ! make -j$(nproc --all) O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 $DTC_ARGS -C "$MODULES_SRC/$module" M="$MODULES_SRC/$module" KERNEL_SRC="$(pwd)" OUT_DIR="$(pwd)/out" TARGET_PRODUCT=$TARGET; then
            echo_w "Failed building $module, continuing"
            continue
        fi
        if ! make -j$(nproc --all) O=out ARCH=arm64 LLVM=1 LLVM_IAS=1 $DTC_ARGS -C "$MODULES_SRC/$module" M="$MODULES_SRC/$module" KERNEL_SRC="$(pwd)" OUT_DIR="$(pwd)/out" TARGET_PRODUCT=$TARGET INSTALL_MOD_PATH=modules INSTALL_MOD_STRIP=1 modules_install; then
            echo_w "Failed installing $module, continuing"
        fi
    done

    # Determine modules lists - warm uses modules.list.msm.warm (with pitti fallback)
    # Original script used waipio; for warm we try warm, then pitti, then pineapple
    first_stage_modules=""
    if [ -f "modules.list.msm.warm" ]; then
        first_stage_modules="$(cat modules.list.msm.warm)"
    elif [ -f "modules.list.msm.pitti" ]; then
        first_stage_modules="$(cat modules.list.msm.pitti)"
    elif [ -f "modules.list.msm.pineapple" ]; then
        first_stage_modules="$(cat modules.list.msm.pineapple)"
    fi

    # second_stage and vendor_dlkm may not exist for warm (only msm list); handle gracefully
    second_stage_modules=""
    if [ -f "modules.list.second_stage" ]; then
        second_stage_modules="$(cat modules.list.second_stage)"
    fi
    if [ -f "modules.list.second_stage.$TARGET_CFG" ]; then
        second_stage_modules="$second_stage_modules $(cat modules.list.second_stage.$TARGET_CFG)"
    fi
    if [ -f "modules.list.second_stage.warm" ]; then
        second_stage_modules="$second_stage_modules $(cat modules.list.second_stage.warm)"
    fi

    vendor_dlkm_modules=""
    if [ -f "modules.list.vendor_dlkm" ]; then
        vendor_dlkm_modules="$(cat modules.list.vendor_dlkm)"
    fi
    if [ -f "modules.list.vendor_dlkm.$TARGET_CFG" ]; then
        vendor_dlkm_modules="$vendor_dlkm_modules $(cat modules.list.vendor_dlkm.$TARGET_CFG)"
    fi

    # For warm/pitti, all modules in msm.warm are considered first_stage if no vendor_dlkm split
    # If vendor_dlkm empty, treat warm list as vendor_dlkm alternative? We'll keep as first_stage
    # Check for system_dlkm - some kernels have separate, but warm uses blocklist only

    if [ -z "$modules_out" ] || [ ! -d "$modules_out" ]; then
        modules_out="out/modules/lib/modules/$(ls -t out/modules/lib/modules/ 2>/dev/null | head -n1)"
    fi
    if [ -z "$modules_out" ] || [ ! -d "$modules_out" ]; then
        echo_e "modules_out not found - modules_install may have failed"
        return 1
    fi

    rm -rf "$VBOOT_DIR" && mkdir -p "$VBOOT_DIR"
    rm -rf "$VDLKM_DIR" && mkdir -p "$VDLKM_DIR"

    # Use warm or pitti blocklist, fallback to generic
    BLOCKLIST_SRC=""
    for cand in "modules.vendor_blocklist.msm.warm" "modules.vendor_blocklist.msm.pitti" "modules.vendor_blocklist.msm.pineapple" "modules.vendor_blocklist.msm.waipio"; do
        if [ -f "$cand" ]; then BLOCKLIST_SRC="$cand"; break; fi
    done

    echo_i "Copying first stage modules..."
    # Clear load files
    : > "$VBOOT_DIR/modules.load"
    : > "$VBOOT_DIR/modules.load.recovery"
    : > "$VDLKM_DIR/modules.load"
    for module in $first_stage_modules; do
        # skip comments/empty
        [[ "$module" == \#* ]] && continue
        [ -z "$module" ] && continue
        mod_path=$(find "$modules_out" -name "$module" -print -quit 2>/dev/null)
        if [ -z "$mod_path" ]; then
            echo_w "Could not locate $module, skipping!"
            continue
        fi
        cp "$mod_path" "$VBOOT_DIR/"
        echo "$module" >> "$VBOOT_DIR/modules.load"
        echo "$module" >> "$VBOOT_DIR/modules.load.recovery"
        echo "$module"
    done

    if [ -n "$second_stage_modules" ]; then
        echo_i "Copying second stage modules..."
        for module in $second_stage_modules; do
            [[ "$module" == \#* ]] && continue
            [ -z "$module" ] && continue
            mod_path=$(find "$modules_out" -name "$module" -print -quit 2>/dev/null)
            if [ -z "$mod_path" ]; then
                echo_w "Could not locate $module, skipping!"
                continue
            fi
            cp "$mod_path" "$VBOOT_DIR/"
            cp "$mod_path" "$VDLKM_DIR/"
            echo "$module" >> "$VBOOT_DIR/modules.load.recovery"
            echo "$module" >> "$VDLKM_DIR/modules.load"
            echo "$module"
        done
    fi

    if [ -n "$vendor_dlkm_modules" ]; then
        echo_i "Copying vendor_dlkm modules..."
        for module in $vendor_dlkm_modules; do
            [[ "$module" == \#* ]] && continue
            [ -z "$module" ] && continue
            mod_path=$(find "$modules_out" -name "$module" -print -quit 2>/dev/null)
            if [ -z "$mod_path" ]; then
                echo_w "Could not locate $module, skipping!"
                continue
            fi
            cp "$mod_path" "$VDLKM_DIR/"
            echo "$module" >> "$VDLKM_DIR/modules.load"
            echo "$module"
        done
    fi

    # If no vendor_dlkm list, duplicate first_stage to vendor_dlkm for compatibility if device expects it
    if [ -z "$vendor_dlkm_modules" ] && [ -z "$second_stage_modules" ]; then
        echo_w "No vendor_dlkm list - using first_stage as base for both"
        # Keep as is, but ensure vendor_dlkm also has copies for device that expects separate
        # Optional: copy all to VDLKM as well
        # cp $VBOOT_DIR/*.ko $VDLKM_DIR/ 2>/dev/null || true
        # cat $VBOOT_DIR/modules.load > $VDLKM_DIR/modules.load 2>/dev/null || true
        :
    fi

    for dest_dir in "$VBOOT_DIR" "$VDLKM_DIR"; do
        if [ -n "$BLOCKLIST_SRC" ] && [ -f "$BLOCKLIST_SRC" ]; then
            cp "$BLOCKLIST_SRC" "$dest_dir/modules.blocklist"
        fi
        if [ -f "$modules_out/modules.alias" ]; then
            cp "$modules_out/modules."{alias,dep,softdep} "$dest_dir/" 2>/dev/null || true
        fi
    done

    # Fix dep paths
    if [ -f "$VBOOT_DIR/modules.dep" ]; then
        sed -E -i 's|([^: ]*/)([^/]*\.ko)([:]?)([ ]\|$)|/lib/modules/\2\3\4|g' "$VBOOT_DIR/modules.dep"
    fi
    if [ -f "$VDLKM_DIR/modules.dep" ]; then
        sed -E -i 's|([^: ]*/)([^/]*\.ko)([:]?)([ ]\|$)|/vendor_dlkm/lib/modules/\2\3\4|g' "$VDLKM_DIR/modules.dep"
    fi

    # Also keep copy in out/dist
    mkdir -p out/dist
    cp -r "$VBOOT_DIR" out/dist/ 2>/dev/null || true
    cp -r "$VDLKM_DIR" out/dist/ 2>/dev/null || true
    echo_i "Modules staged to $VBOOT_DIR and $VDLKM_DIR"
    if [ "$COPY_ENABLED" = false ]; then
        echo_i "Also available in out/dist/ (standalone build)"
    fi
}

build_dtbs() {
    echo_i "Building dtbs..."
    m dtbs

    rm -rf out/dtbs{,-base}
    mkdir out/dtbs{,-base}
    # Move matching DTBs/DTBOs to base, handle warm pitti case
    # For warm, DTB_WILDCARD=pitti, DTBO=warm-sm4635-overlay
    # Need to handle if DTB files are named pitti*.dtb
    set +e
    mv out/arch/arm64/boot/dts/vendor/qcom/"$DTB_WILDCARD"*.dtb out/dtbs-base/ 2>/dev/null
    mv out/arch/arm64/boot/dts/vendor/qcom/"$DTBO_WILDCARD".dtbo out/dtbs-base/ 2>/dev/null
    # fallback - if wildcards didn't match, try exact
    if [ ! -f out/dtbs-base/*.dtb 2>/dev/null ]; then
        mv out/arch/arm64/boot/dts/vendor/qcom/*.dtb out/dtbs-base/ 2>/dev/null || true
    fi
    if [ ! -f out/dtbs-base/*.dtbo 2>/dev/null ]; then
        mv out/arch/arm64/boot/dts/vendor/qcom/*.dtbo out/dtbs-base/ 2>/dev/null || true
    else
        rm -f out/arch/arm64/boot/dts/vendor/qcom/*.dtbo 2>/dev/null || true
    fi
    set -e

    # Use merge script if exists at ../../build/android/merge_dtbs.py (original AOSPA path)
    MERGE_SCRIPT="../../build/android/merge_dtbs.py"
    if [ ! -f "$MERGE_SCRIPT" ]; then
        MERGE_SCRIPT="$KP_ROOT/build/android/merge_dtbs.py"
    fi
    if [ ! -f "$MERGE_SCRIPT" ]; then
        # fallback: try kernel's scripts/dtc/merge ?
        MERGE_SCRIPT="scripts/dtc/merge_dtbs.py"
    fi
    if [ -f "$MERGE_SCRIPT" ]; then
        python3 "$MERGE_SCRIPT" out/dtbs-base out/arch/arm64/boot/dts/vendor/qcom/ out/dtbs || {
            echo_w "merge_dtbs.py failed, falling back to simple copy"
            cp out/dtbs-base/* out/dtbs/ 2>/dev/null || true
            cp out/arch/arm64/boot/dts/vendor/qcom/*.dtb out/dtbs/ 2>/dev/null || true
            cp out/arch/arm64/boot/dts/vendor/qcom/*.dtbo out/dtbs/ 2>/dev/null || true
        }
    else
        echo_w "merge_dtbs.py not found, copying dtbs directly"
        cp out/dtbs-base/* out/dtbs/ 2>/dev/null || true
        cp out/arch/arm64/boot/dts/vendor/qcom/*.dtb out/dtbs/ 2>/dev/null || true
    fi

    mkdir -p "$(dirname "$DTB_COPY_TO")"
    if [ -d "$DTB_COPY_TO" ]; then
        rm -f "$DTB_COPY_TO"/*.dtb
        cp out/dtbs/*.dtb "$DTB_COPY_TO/" 2>/dev/null || true
        echo_i "Copied dtb(s) to $DTB_COPY_TO"
    else
        mkdir -p "$(dirname "$DTB_COPY_TO")"
        rm -f "$DTB_COPY_TO"
        cat out/dtbs/*.dtb > "$DTB_COPY_TO" 2>/dev/null || cp out/dtbs/*.dtb "$DTB_COPY_TO" 2>/dev/null || true
        echo_i "Generated DTB at $DTB_COPY_TO"
    fi

    # DTBO
    mkdir -p "$(dirname "$DTBO_COPY_TO")"
    if command -v mkdtboimg.py >/dev/null 2>&1; then
        mkdtboimg.py create "$DTBO_COPY_TO" --page_size=4096 out/dtbs/*.dtbo 2>/dev/null && echo_i "Generated dtbo.img to $DTBO_COPY_TO" || echo_w "mkdtboimg.py failed"
    elif [ -x "$PREBUILTS_DIR/bin/mkdtboimg.py" ]; then
        "$PREBUILTS_DIR/bin/mkdtboimg.py" create "$DTBO_COPY_TO" --page_size=4096 out/dtbs/*.dtbo && echo_i "Generated dtbo.img to $DTBO_COPY_TO" || echo_w "mkdtboimg failed"
    else
        echo_w "mkdtboimg.py not found - dtbo.img not generated (check out/dtbs/*.dtbo)"
        ls out/dtbs/*.dtbo 2>/dev/null | head || true
    fi
    mkdir -p out/dist
    cp out/dtbs/* out/dist/ 2>/dev/null || true
    cp "$DTB_COPY_TO" out/dist/ 2>/dev/null || true
    cp "$DTBO_COPY_TO" out/dist/ 2>/dev/null || true
}

##
## Main logic starts here
##

# Setup PATH
if [ -n "$TC_DIR" ] && [ -d "$TC_DIR/bin" ]; then
    export PATH="$TC_DIR/bin:$PREBUILTS_DIR/bin:$PATH"
    echo_i "Using clang at $TC_DIR"
elif command -v clang >/dev/null 2>&1; then
    echo_w "TC_DIR not found, using system clang: $(which clang)"
    export PATH="$PREBUILTS_DIR/bin:$PATH"
else
    echo_w "No clang found at $TC_DIR, trying PATH"
    export PATH="$PREBUILTS_DIR/bin:$PATH"
fi

export LOCALVERSION="$(get_trees_rev)"

$DO_CLEAN && {
    rm -rf out
    # also clean modules repo out if requested
    # rm -rf ../$MODULES_REPO/out 2>/dev/null || true
    echo_i "Cleaned output directories."
}

mkdir -p out

echo_i "Generating config..."
echo "DEFCONFIG: $DEFCONFIG"
echo "DEFCONFIGS: $DEFCONFIGS"
m "$DEFCONFIG"
# merge_config.sh may fail if fragments missing - handle gracefully
for cfg in $DEFCONFIGS; do
    if [ ! -f "arch/arm64/configs/$cfg" ]; then
        echo_w "Config $cfg not found, skipping"
        continue
    fi
done
if [ -n "$DEFCONFIGS" ]; then
    # Only pass existing configs
    EXISTING=""
    for cfg in $DEFCONFIGS; do
        [ -f "arch/arm64/configs/$cfg" ] && EXISTING="$EXISTING $cfg"
    done
    if [ -n "$EXISTING" ]; then
        m ./scripts/kconfig/merge_config.sh $EXISTING
    fi
fi
# Also merge vendor/${TARGET_CFG}_GKI.config if exists and not already in list
if [ -f "arch/arm64/configs/vendor/${TARGET_CFG}_GKI.config" ] && [[ "$DEFCONFIGS" != *"${TARGET_CFG}_GKI"* ]]; then
    m ./scripts/kconfig/merge_config.sh "vendor/${TARGET_CFG}_GKI.config"
fi

scripts/config --file out/.config \
    --set-str LOCALVERSION "-$BRANCH" \
    -d LOCALVERSION_AUTO \
    -m CONFIG_KSU 2>/dev/null || echo_w "KSU config not found, skipping"

# Fix for sipa.c frame-larger-than (2752 > 2048) on clang - raise limit to 3072
scripts/config --file out/.config --set-val CONFIG_FRAME_WARN 3072 2>/dev/null || true
# Disable hdmi codec that requires mm_ext_display symbols not available in standalone audio build
# If you need hdmi, build mm-drivers/msm_ext_display first and ensure KBUILD_EXTRA_SYMBOLS
scripts/config --file out/.config -d CONFIG_SND_SOC_MSM_HDMI_CODEC_RX 2>/dev/null || true
# Enable display/mi_disp and spec_sync for pitti warm (display needs these)
scripts/config --file out/.config -e CONFIG_DRM_MSM_MI_DISP 2>/dev/null || true
scripts/config --file out/.config -e CONFIG_QCOM_SPEC_SYNC 2>/dev/null || true
# UBWCP heap intentionally not enabled as builtin - would require mem_buf etc. (causes vmlinux mem_buf_vmperm_* errors)
# mm-sys-kernel/ubwcp uses weak stub in ubwcp_stub.c when heap disabled
# Alternative: disable the problematic driver via config if you don't need it
# scripts/config --file out/.config -d CONFIG_SND_SOC_SIA8001 2>/dev/null || true

$NO_LTO && {
    scripts/config --file out/.config \
        --set-str LOCALVERSION "-${BRANCH}-nolto" \
        -d LTO_CLANG_FULL -e LTO_NONE 2>/dev/null || true
    echo_i "Disabled LTO!"
}

$ONLY_CONFIG && exit 0

if $ONLY_KERNEL; then build_kernel
elif $ONLY_DTB; then build_dtbs
elif $ONLY_MODULES; then build_modules
else {
    build_kernel
    build_modules
    build_dtbs
}; fi

echo_i "Completed in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
if [ "$COPY_ENABLED" = false ]; then
    echo_i "Standalone build: artifacts in out/dist/, out/arch/arm64/boot/Image, out/dtbs/, modules in out/modules/"
    echo "To enable copy to device tree, create .build.rc with:"
    echo "  SRC_ROOT=/path/to/aospa"
fi
