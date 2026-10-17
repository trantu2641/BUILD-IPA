# RootRemote Build Kit

Includes an Xcode project and a GitHub Actions workflow. You do not need Xcode installed on your own Windows/Linux computer; GitHub's hosted macOS runner builds the app.

## Build IPA
1. Upload all files in this folder to a GitHub repository. Keep the `.github` folder.
2. Push to `main` or `master`, or go to **Actions → Build RootRemote IPA → Run workflow**.
3. Download the `RootRemote-unsigned-IPA` artifact when the run finishes.

The result is an unsigned IPA. This workflow has not been run from this chat, so build success is not verified. A compatible installer/signing method may be needed for your jailbroken iPhone.

Current app: SwiftUI connection UI, TCP/token transport, ping/status, tap, Back and Home commands.
Not yet implemented: Android screen streaming, H.264 display, WebRTC, robust auto-reconnect, or production security.
Use the matching Android agent prototype and keep it behind a private VPN. Do not expose root control services publicly.
