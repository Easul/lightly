# Lightly Life Runtime companion

This is a pure Android companion APK for running the Android builds of
MindGit and Life Record. It has no Flutter engine and no business UI.

The service loads executables from its private runtime directory:

```text
/data/user/0/lightly.tool.plugin.liferuntime/files/runtime/
  bin/mindgit
  bin/liferecord
  workspaces/
  data/
  logs/
```

The first release intentionally exposes only fixed start/stop operations over
the signature-protected AIDL service. It does not expose arbitrary command
execution or a terminal. Android builds of `git`, `ssh`, and optional `rg`
will be added to `runtime/bin` as versioned tool assets; ordinary glibc Linux
binaries are not compatible with Android's bionic runtime.

The default bind address is `127.0.0.1`. LAN binding is an explicit caller
option and must be paired with application authentication before release.
