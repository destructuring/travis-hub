all: ready

ready:
	@git submodule update --init --recursive
	@bundle check --path vendor/bundle 2>&1 >/dev/null || bundle --local --standalone --path vendor/bundle
