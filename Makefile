# xcode-select still points at CommandLineTools on this machine and switching it
# needs sudo, so every recipe sets DEVELOPER_DIR itself.
export DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
# `simctl` is spawned by the test runner for diagnostics and resolves through
# the ACTIVE developer dir, not this variable, so it fails while
# `xcode-select -p` still points at CommandLineTools. Putting Xcode's bin
# directory first gives those child processes a chance to find it.
export PATH := /Applications/Xcode.app/Contents/Developer/usr/bin:$(PATH)

DEST := platform=iOS Simulator,name=iPhone 17 Pro

# UI tests get their OWN simulator.
#
# Sharing "iPhone 17 Pro" with anything else — another agent, an open Xcode, a
# second test run — produced runs that silently executed a subset of the suite
# with no assertion failure and no crash, just a truncated result bundle. A
# gate cannot share a device with other work.
RUN_ID := $(shell echo $$$$)
UITEST_DEVICE := AL-uitest-$(RUN_ID)
UITEST_RUNTIME := com.apple.CoreSimulator.SimRuntime.iOS-26-5
UITEST_TYPE := com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro
BUNDLE := com.apartmentlist.prototype.map
APP := .build/app/Build/Products/Debug-iphonesimulator/ApartmentListMap.app

.PHONY: project build test uitest uitest-device uitest-screenshots run screenshot clean

project:
	xcodegen generate

build: project
	xcodebuild -project ApartmentListMap.xcodeproj -scheme ApartmentListMap \
	  -destination '$(DEST)' -derivedDataPath .build/app build

# The generated .xcodeproj shadows the package's own schemes, so it is parked
# for the duration of the test run and restored afterwards.
test:
	@mv ApartmentListMap.xcodeproj .xcodeproj.parked 2>/dev/null || true
	@xcodebuild -scheme ApartmentListMap-Package -destination '$(DEST)' \
	  -derivedDataPath .build/dd test; status=$$?; \
	  mv .xcodeproj.parked ApartmentListMap.xcodeproj 2>/dev/null || true; \
	  exit $$status

run: build
	-xcrun simctl boot "iPhone 17 Pro"
	xcrun simctl install "iPhone 17 Pro" "$(APP)"
	SIMCTL_CHILD_ALLoopsLaunchMoment=0 xcrun simctl launch "iPhone 17 Pro" $(BUNDLE)

screenshot:
	xcrun simctl io "iPhone 17 Pro" screenshot --type=png shot.png

# UI tests, verified from the result BUNDLE rather than stdout.
#
# Three things made stdout untrustworthy, all observed on this machine:
#   1. xcodebuild emits several "Executed N tests" summary lines per run, and
#      they disagree — one run logged 4 passing test cases while every summary
#      line said "Executed 2 tests".
#   2. A suite was seen reporting PASSED having executed ZERO tests.
#   3. The process exits "** TEST FAILED **" when every test passed, because
#      diagnostics collection cannot find `simctl`.
#
# So neither the summary nor the exit code gates anything. `xcresulttool` reads
# the structured result, and the count is asserted against a floor: a suite
# that silently runs nothing is worse than no suite, because it launders
# confidence.
# A mismatch means one of two things, and they are not interchangeable:
# either someone ADDED a test (bump this deliberately) or the run TRUNCATED
# (do not bump; find out why). Bumping to make it green defeats the check.
UITEST_COUNT := 5
BUNDLE_PATH := .build/uitest-$(RUN_ID).xcresult

# Creates the device on first use and reuses it afterwards.
uitest-device:
	@if ! xcrun simctl list devices | grep -q '$(UITEST_DEVICE) ('; then \
	  echo "creating $(UITEST_DEVICE)"; \
	  xcrun simctl create '$(UITEST_DEVICE)' $(UITEST_TYPE) $(UITEST_RUNTIME) > /dev/null; \
	fi
	@xcrun simctl bootstatus '$(UITEST_DEVICE)' -b > /dev/null 2>&1 || true

uitest: project uitest-device
	@rm -rf $(BUNDLE_PATH)
	@mkdir -p .build
	-@xcodebuild -project ApartmentListMap.xcodeproj -scheme ApartmentListMap \
	  -destination 'platform=iOS Simulator,name=$(UITEST_DEVICE)' -derivedDataPath .build/uitest \
	  -resultBundlePath $(BUNDLE_PATH) \
	  -only-testing:ApartmentListMapUITests/PresentationTests test > .build/uitest-$(RUN_ID).log 2>&1
	@python3 Scripts/check-uitest.py $(UITEST_COUNT) .build/uitest-$(RUN_ID).log
	@xcrun simctl delete '$(UITEST_DEVICE)' > /dev/null 2>&1 || true

# Regenerates every image in Screenshots/ by driving the app.
uitest-screenshots: project uitest-device
	@rm -rf /tmp/al-shots
	-@xcodebuild -project ApartmentListMap.xcodeproj -scheme ApartmentListMap \
	  -destination 'platform=iOS Simulator,name=$(UITEST_DEVICE)' -derivedDataPath .build/shots \
	  -only-testing:ApartmentListMapUITests/AppScreenshots test > .build/shots-$(RUN_ID).log 2>&1
	@count=$$(ls /tmp/al-shots/*.png 2>/dev/null | wc -l | tr -d ' '); \
	if [ "$$count" = "0" ]; then echo "FAIL: no screenshots produced"; tail -20 .build/shots-$(RUN_ID).log; exit 1; fi; \
	cp /tmp/al-shots/*.png Screenshots/; \
	echo "wrote $$count screenshots to Screenshots/"
	@xcrun simctl delete '$(UITEST_DEVICE)' > /dev/null 2>&1 || true

clean:
	rm -rf .build ApartmentListMap.xcodeproj
