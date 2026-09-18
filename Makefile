VERSION := $(shell ruby -r ./lib/gsc/version -e 'puts GSC::VERSION')
GEM_FILE := gsc-cli-$(VERSION).gem
GH_TOKEN ?= $(shell printf "host=github.com\nprotocol=https\n\n" | git credential fill 2>/dev/null | grep '^password=' | cut -d= -f2)

.PHONY: all build test install git-push gem-push github-release release publish clean help

all: build

help:
	@echo "Available commands:"
	@echo "  make build          - Build standalone binary (dist/gsc) and gem package ($(GEM_FILE))"
	@echo "  make test           - Run syntax checks and test suite"
	@echo "  make install        - Install standalone binary to ~/.local/bin/gsc"
	@echo "  make git-push       - Stage, commit, create git tag v$(VERSION), and push to GitHub with tags"
	@echo "  make gem-push       - Build and push $(GEM_FILE) to RubyGems.org"
	@echo "  make github-release - Create GitHub release for v$(VERSION) and attach binary assets"
	@echo "  make release        - Full release: test -> build -> git-push -> gem-push -> github-release"
	@echo "  make publish        - Alias for 'make release'"
	@echo "  make clean          - Remove built *.gem packages"

build:
	@echo "🔨 Building standalone binary (v$(VERSION))..."
	rake build:standalone
	cp dist/gsc bin/gsc
	@echo "💎 Building RubyGem package ($(GEM_FILE))..."
	gem build gsc.gemspec

test:
	@echo "🧪 Running syntax and unit tests..."
	rake test

install:
	@echo "📦 Installing standalone binary to ~/.local/bin/gsc..."
	rake install:standalone

git-push:
	@echo "📦 Staging changes for v$(VERSION)..."
	git add -A
	@if git diff-index --quiet HEAD; then \
		echo "ℹ️  Working directory clean, nothing to commit."; \
	else \
		git commit -m "release: v$(VERSION) - sync release binaries and gemspec"; \
	fi
	@if git rev-parse "v$(VERSION)" >/dev/null 2>&1; then \
		echo "ℹ️  Git tag v$(VERSION) already exists."; \
	else \
		echo "🏷️  Creating git tag v$(VERSION)..."; \
		git tag -a "v$(VERSION)" -m "Release v$(VERSION)"; \
	fi
	@echo "🚀 Pushing to GitHub (origin main --tags)..."
	git push origin main --tags

gem-push: build
	@echo "💎 Pushing $(GEM_FILE) to RubyGems.org..."
	gem push $(GEM_FILE)

github-release: build
	@echo "🐙 Creating GitHub release for v$(VERSION)..."
	@if GH_TOKEN="$(GH_TOKEN)" gh release view "v$(VERSION)" >/dev/null 2>&1; then \
		echo "ℹ️  GitHub release v$(VERSION) already exists. Uploading latest assets..."; \
		GH_TOKEN="$(GH_TOKEN)" gh release upload "v$(VERSION)" dist/gsc $(GEM_FILE) --clobber; \
	else \
		GH_TOKEN="$(GH_TOKEN)" gh release create "v$(VERSION)" dist/gsc $(GEM_FILE) \
			--title "v$(VERSION)" \
			--generate-notes; \
	fi
	@echo "✅ GitHub release v$(VERSION) published!"

release: test build git-push gem-push github-release
	@echo ""
	@echo "🎉 v$(VERSION) successfully published to GitHub and RubyGems.org!"
	@echo "   GitHub:         https://github.com/ApollosWave/gsc-cli"
	@echo "   GitHub Release: https://github.com/ApollosWave/gsc-cli/releases/tag/v$(VERSION)"
	@echo "   RubyGems:       https://rubygems.org/gems/gsc-cli"

publish: release

clean:
	@echo "🧹 Cleaning built gem files..."
	rm -f *.gem
