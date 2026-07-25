#!/usr/bin/env bash

# Project-local Android/Flutter toolchain for NetTools Mobile.
NETTOOLS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export JAVA_HOME="$NETTOOLS_ROOT/.tooling/jdk"
export ANDROID_HOME="$NETTOOLS_ROOT/.tooling/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export GRADLE_USER_HOME="$NETTOOLS_ROOT/.tooling/gradle-home"
export PUB_CACHE="$NETTOOLS_ROOT/.tooling/pub-cache"
export FLUTTER_SUPPRESS_ANALYTICS=true

export PATH="$NETTOOLS_ROOT/.tooling/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

unset NETTOOLS_ROOT
