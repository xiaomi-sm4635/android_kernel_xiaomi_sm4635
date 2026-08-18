#!/bin/bash

export DEVICE_CODENAME="warm"
export ARCH=arm64
export SUBARCH=arm64

# Base GKI defconfig + Xiaomi SM4635 Warm vendor config
export DEFCONFIG="gki_defconfig"
export VENDOR_CONFIG="vendor/warm_GKI.config"

# Toolchain settings
export USE_LLVM=1
export CC=clang
export LD=ld.lld
export JOBS=$(nproc --all)

# Directory paths
export ROOT_DIR="$(pwd)"
export OUT_DIR="${ROOT_DIR}/output"
export TC_DIR="${ROOT_DIR}/toolchains/clang"
export SRC_DIR="${ROOT_DIR}"
