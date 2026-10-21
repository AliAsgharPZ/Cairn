# Dev environment for Cairn on the Linux build VM — source me before building.
export JAVA_HOME="$HOME/devtools/jdk17"
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export PATH="$HOME/devtools/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
# Java resolves user.home to /root in this sandbox (ephemeral overlay), so pin
# Gradle's user home to the persistent volume explicitly.
export GRADLE_USER_HOME="$HOME/.gradle"
# JVM proxy flags are derived from the environment's proxy variables at
# source time (this sandbox routes egress through an authenticated proxy that
# Java does not pick up by itself). The values are never written into the repo.
if [ -n "${https_proxy:-}" ]; then
  eval "$(python3 - <<'PY'
import os, shlex, urllib.parse
u = urllib.parse.urlparse(os.environ.get('https_proxy', ''))
opts = ['-Xmx1536m']
if u.hostname:
    opts += [f'-Dhttp.proxyHost={u.hostname}', f'-Dhttp.proxyPort={u.port}',
             f'-Dhttps.proxyHost={u.hostname}', f'-Dhttps.proxyPort={u.port}']
    if u.username:
        opts += [f'-Dhttp.proxyUser={urllib.parse.unquote(u.username)}',
                 f'-Dhttps.proxyUser={urllib.parse.unquote(u.username)}']
    if u.password:
        opts += [f'-Dhttp.proxyPassword={urllib.parse.unquote(u.password)}',
                 f'-Dhttps.proxyPassword={urllib.parse.unquote(u.password)}']
    opts += ['-Dhttp.nonProxyHosts=localhost', '-Dhttps.nonProxyHosts=localhost']
print('export GRADLE_OPTS=' + shlex.quote(' '.join(opts)))
PY
)"
else
  export GRADLE_OPTS="-Xmx1536m"
fi
# NOTE: do not set org.gradle.daemon=false here — in this sandbox the
# disposable daemon sees stdin EOF and exits before the client can dispatch.
