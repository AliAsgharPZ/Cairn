# Dev environment for Cairn on the Linux build VM — source me before building.
export JAVA_HOME="$HOME/devtools/jdk17"
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export PATH="$HOME/devtools/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
# Keep Gradle modest on this 2-vCPU / 8 GB VM.
export GRADLE_OPTS="-Xmx1536m -Dorg.gradle.daemon=false"
