EXEC     := Saira
CONFIG   := debug

## Build products live OUTSIDE this directory, for the same reason the .app does.
##
## If this tree is ever iCloud/file-provider synced (~/Desktop, ~/Documents), the provider
## mutates files inside .build while the compiler is using them — producing "input file was
## modified during the build" on random object files. ~/Library/Caches is never synced.
SCRATCH  := $(HOME)/Library/Caches/SairaBuild/scratch
BUILD    := $(SCRATCH)/$(CONFIG)/$(EXEC)

## Toolchain workaround for a Mac with only the Command Line Tools (no full Xcode).
##
## Swift 6.4's default build system ("swiftbuild") fails to initialise at all under the CLT
## ("Unknown error parsing property list"), even for an empty package. The native build
## system works, but against the macOS 27 SDK SwiftUI's `@State` is a macro whose plugin
## (SwiftUIMacros) only ships inside Xcode. The macOS 26 SDK still declares it as a property
## wrapper, and the app's deployment target is 26 anyway — so build against that.
##
## With full Xcode installed, override: `make SWIFT_FLAGS=`.
SDK26       := $(shell xcrun --sdk macosx26.5 --show-sdk-path 2>/dev/null || xcrun --sdk macosx26 --show-sdk-path 2>/dev/null)
ifneq ($(strip $(SDK26)),)
SWIFT_FLAGS ?= --build-system native --sdk "$(SDK26)"
## Pointing at a non-default SDK also loses the toolchain's swift-testing framework path,
## so the tests are told where it lives.
TESTING_FW  := $(shell xcode-select -p)/Library/Developer/Frameworks
TEST_FLAGS  ?= -Xswiftc -F -Xswiftc "$(TESTING_FW)" -Xlinker -F -Xlinker "$(TESTING_FW)" \
               -Xlinker -rpath -Xlinker "$(TESTING_FW)"
endif

## The bundle is assembled and signed OUTSIDE this directory on purpose: a file provider
## can stamp com.apple.FinderInfo onto files inside an .app faster than we can strip them,
## and codesign hard-refuses anything carrying it.
STAGE    := $(HOME)/Library/Caches/SairaBuild
APPNAME  := Saira.app
BUNDLE   := $(STAGE)/$(APPNAME)
CONTENTS := $(BUNDLE)/Contents

## TCC keys the Accessibility grant to the code signature, so an ad-hoc signature — which
## changes on every build — makes you re-grant after every `make`. Any *stable* identity fixes
## that, in order of preference:
##   1. a Developer ID, if the Mac has one;
##   2. a self-signed "Saira Local Signing" code-signing certificate (Keychain Access ▸
##      Certificate Assistant ▸ Create a Certificate… ▸ type Code Signing). Self-signed certs are
##      "not trusted", so it's looked up without -v — codesign doesn't need trust, TCC doesn't
##      either, it only needs the same certificate every time;
##   3. ad-hoc ("-"), which works but forgets the Accessibility grant on every rebuild.
LOCAL_ID := Saira Local Signing
SIGN_ID := $(shell security find-identity -v -p codesigning 2>/dev/null \
             | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/')
ifeq ($(strip $(SIGN_ID)),)
SIGN_ID := $(shell security find-identity -p codesigning 2>/dev/null \
             | grep -F "$(LOCAL_ID)" | head -1 | sed -E 's/.*"(.*)".*/\1/')
endif
ifeq ($(strip $(SIGN_ID)),)
SIGN_ID := -
endif

.PHONY: all build app run install test clean icon

all: app

build:
	swift build -c $(CONFIG) $(SWIFT_FLAGS) --scratch-path "$(SCRATCH)"

test:
	swift test $(SWIFT_FLAGS) $(TEST_FLAGS) --scratch-path "$(SCRATCH)" --filter VectorTests

## Regenerates AppIcon.icns from Tools/makeicon.swift. Not a dependency of `app` — the
## icon rarely changes and rendering 10 PNGs on every build is wasted time.
icon:
	@swift Tools/makeicon.swift
	@iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
	@echo "wrote Resources/AppIcon.icns"

## Assemble a real .app bundle. TCC (microphone + Accessibility) keys on bundle identity
## and code signature, so the raw SwiftPM binary can't be used directly.
app: build
	@rm -rf "$(BUNDLE)"
	@mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	@cp "$(BUILD)" "$(CONTENTS)/MacOS/$(EXEC)"
	@cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$(CONTENTS)/Resources/"; fi
	@printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	@xattr -cr "$(BUNDLE)"
	@codesign --force --sign "$(SIGN_ID)" \
		--entitlements Resources/$(EXEC).entitlements \
		--options runtime \
		--timestamp=none \
		"$(BUNDLE)"
	@echo "built $(BUNDLE)  [signed: $(SIGN_ID)]"

## Only ever targets the Saira executable — never another dictation app.
run: app
	@pkill -x $(EXEC) 2>/dev/null || true
	@open "$(BUNDLE)"

## Installing to /Applications keeps the path stable, and "Start at login" requires it.
install: app
	@pkill -x $(EXEC) 2>/dev/null || true
	@rm -rf "/Applications/$(APPNAME)"
	@cp -R "$(BUNDLE)" "/Applications/$(APPNAME)"
	@open "/Applications/$(APPNAME)"
	@echo "installed to /Applications/$(APPNAME)"

clean:
	@rm -rf .build "$(STAGE)" "$(SCRATCH)"
