# Live-only PiP and legacy preview cleanup

The page surface is intentionally live-only: `NotionWebSession` displays the embedded Notion page, and the app has no native preview or preview-cache UI.

Older builds may have left derived preview files under `Application Support/Perch/NativePageCache`. The app does not inspect or delete that directory at launch or during an upgrade. It removes the directory only after the user explicitly disconnects their personal Notion token.

`AppRuntime` receives a small cache-cleaning dependency and an explicit directory URL. The filesystem implementation first checks that the directory exists, then removes that exact directory. Cache-cleanup failure is logged separately after token removal; it does not change the disconnected state or imply that token removal failed.
