## Install Notes (Unsigned Build)

This release artifact is currently unsigned and not notarized.
If macOS says the app is damaged, run:

```bash
xattr -dr com.apple.quarantine /Applications/QatVasl.app
open /Applications/QatVasl.app
```

See `INSTALL_UNSIGNED.md` for full instructions.
