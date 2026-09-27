.PHONY: generate open clean build test lint check hooks licenses preflight status testflight submit demo-prepare demo demo-record web-deploy convex-deploy

PROJECT = WizMark.xcodeproj
SCHEME  = WizMark
SIM     = platform=iOS Simulator,name=iPhone 16 Pro

# ── 開発 ───────────────────────────────────────────────────────────────────
generate:
	xcodegen generate

open: generate
	open $(PROJECT)

clean:
	rm -rf DerivedData build/
	rm -rf $(PROJECT)

build: generate
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(SIM)' -configuration Debug

test: generate
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
		-destination '$(SIM)' -configuration Debug

lint:
	swift-format lint --recursive Sources/WizMark/ || true
	swift-format format --recursive --in-place Sources/WizMark/ || true

# ── リリース ───────────────────────────────────────────────────────────────
# preflight  : ビルド・テスト・Convex 型・戻り値契約・審査適合・秘密情報
# status     : ローカルと App Store Connect の現状
# testflight : 次のビルド番号でアーカイブ〜TestFlight 配信まで
# submit     : 同上に加えてバージョン作成と審査提出まで（VERSION 必須）
check:
	./scripts/check.sh --all

hooks:
	git config core.hooksPath .githooks
	@echo "git フックを有効にしました (.githooks)"

licenses:
	./scripts/generate-licenses.sh

preflight:
	./scripts/preflight.sh

status:
	./scripts/release.sh status

testflight:
	./scripts/release.sh testflight $(ARGS)

submit:
	@test -n "$(VERSION)" || (echo "VERSION を指定してください (例: make submit VERSION=1.0.2)"; exit 1)
	./scripts/release.sh submit --version $(VERSION) $(ARGS)

# ── デモ ───────────────────────────────────────────────────────────────────
# demo-prepare : ビルドして入れ直し、Pro・モックデータ入りで起動
# demo         : Maestro のフローを流してスクリーンショットを撮る
# demo-record  : 録画しながら流す
demo-prepare:
	./scripts/demo.sh prepare

demo:
	./scripts/demo.sh run

demo-record:
	./scripts/demo.sh record

# ── 周辺 ───────────────────────────────────────────────────────────────────
web-deploy:
	cd web && npm run build && npx wrangler pages deploy dist \
		--project-name wizmark-web --branch main

convex-deploy:
	npx convex dev --once
