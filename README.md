# meqat

## Build and test

```
swift test --package-path MeqatCore
xcodebuild -project Meqat.xcodeproj -scheme Meqat -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

## Install

```
brew install masnun-siam/tap/meqat
```

Or download the DMG from the [releases page](https://github.com/masnun-siam/meqat/releases).

## Release

See [docs/release-checklist.md](docs/release-checklist.md).
