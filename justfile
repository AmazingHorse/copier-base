set shell := ["bash", "-euc"]

# Install the pinned render and validation tools.
setup:
    mise install

check: lint test

lint:
    actionlint
    shfmt -d tests/render.sh

test:
    bash tests/render.sh
