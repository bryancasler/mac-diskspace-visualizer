.PHONY: build run debug clean icon

icon:
	bash scripts/make-icon.sh

build:
	bash scripts/build-app.sh

run: build
	open build/DiskVis.app

debug:
	swift build

clean:
	rm -rf .build build
