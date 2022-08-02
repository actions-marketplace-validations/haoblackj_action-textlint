#!/bin/bash

# shellcheck disable=SC2086,SC2089,SC2090

cd "${GITHUB_WORKSPACE}" || exit

TEMP_PATH="$(mktemp -d)"
PATH="${TEMP_PATH}:$PATH"

echo '::group::🐶 Installing reviewdog ... https://github.com/reviewdog/reviewdog'
curl -sfL https://raw.githubusercontent.com/reviewdog/reviewdog/master/install.sh | sh -s -- -b "${TEMP_PATH}" "${REVIEWDOG_VERSION}" 2>&1
echo '::endgroup::'

echo '::group:: Installing textlint ...  https://github.com/textlint/textlint'
if [ -x "./node_modules/.bin/textlint"  ]; then
  echo 'already installed'
else
  echo 'install start'
  if [ -e ./yarn.lock ]; then
    yarn install --immutable --immutable-cache --check-
  else
    npm ci
  fi
fi

if [ -x "./node_modules/.bin/textlint"  ]; then
  npx textlint --version
else
  echo 'This repository was not configured for textlint, process done.'
  exit 1
fi
echo '::endgroup::'

export REVIEWDOG_GITHUB_API_TOKEN="${INPUT_GITHUB_TOKEN}"


echo '::group:: Running textlint with reviewdog 🐶 ...'
textlint_exit_val="0"
reviewdog_exit_val="0"

# shellcheck disable=SC2086
textlint_check_output=$(npx textlint -f checkstyle ${INPUT_TEXTLINT_FLAGS} 2>&1) \
                      || textlint_exit_val="$?"

# shellcheck disable=SC2086
echo "${textlint_check_output}" | reviewdog -f=checkstyle \
        -name="${INPUT_TOOL_NAME}"                        \
        -reporter="${INPUT_REPORTER:-github-pr-review}"   \
        -filter-mode="${INPUT_FILTER_MODE}"               \
        -fail-on-error="${INPUT_FAIL_ON_ERROR}"           \
        -level="${INPUT_LEVEL}"                           \
        ${INPUT_REVIEWDOG_FLAGS} || reviewdog_exit_val="$?"
echo '::endgroup::'

# github-pr-review only diff adding
if [[ "${INPUT_REPORTER}" == "github-pr-review" ]]; then
  echo '::group:: Running textlint fixing report 🐶 ...'
  # fix
  npx textlint --fix ${INPUT_TEXTLINT_FLAGS:-.} || true

  TMPFILE=$(mktemp)
  git diff > "${TMPFILE}"

  git stash -u

  # shellcheck disable=SC2086
  reviewdog                        \
    -f=diff                        \
    -f.diff.strip=1                \
    -name="${INPUT_TOOL_NAME}-fix" \
    -reporter="github-pr-review"   \
    -filter-mode="diff_context"    \
    -level="${INPUT_LEVEL}"        \
    ${INPUT_REVIEWDOG_FLAGS} < "${TMPFILE}"

  git stash drop || true
  echo '::endgroup::'
fi

# Throw error if an error occurred and fail_on_error is true
if [[ "${INPUT_FAIL_ON_ERROR}" == "true"       \
      && ( "${textlint_exit_val}" != "0"       \
           || "${reviewdog_exit_val}" != "0" ) \
   ]]; then
  exit 1
fi

# EOF
