#!/usr/bin/env bash
set -euo pipefail

OWNER="${GITHUB_REPOSITORY_OWNER:-rainbowkillah}"
README_PATH="README.md"
START_MARKER="<!-- currently-building:start -->"
END_MARKER="<!-- currently-building:end -->"
API_URL="https://api.github.com/users/${OWNER}/repos?sort=updated&per_page=6&type=owner"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to update the Currently Building strip." >&2
  exit 1
fi

if [[ ! -f "${README_PATH}" ]]; then
  echo "README.md not found." >&2
  exit 1
fi

curl_args=(
  -fsSL
  -H "Accept: application/vnd.github+json"
  -H "X-GitHub-Api-Version: 2022-11-28"
)

if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

api_response="$(curl "${curl_args[@]}" "${API_URL}" || { echo "Failed to fetch repositories from GitHub API." >&2; exit 1; })"

if ! jq -e 'type == "array"' <<<"${api_response}" >/dev/null 2>&1; then
  echo "GitHub API returned invalid response format." >&2
  exit 1
fi

build_rows="$(jq -r '
  map(select(.fork == false and .archived == false))[:4]
  | map({
      name: .name,
      html_url: .html_url
    })
  | .[]
  | "  <a href=\"\(.html_url)\"><img src=\"https://img.shields.io/static/v1?label=currently%20building&message=\(.name|@uri)&color=0A66C2&style=for-the-badge&logo=github\" alt=\"\(.name | gsub("[&<>\"]"; {"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;"}))\" /></a>"
' <<<"${api_response}")"

if [[ -z "${build_rows}" ]]; then
  echo "No repositories returned from GitHub API; aborting update." >&2
  exit 1
fi

generated_file="$(mktemp)"
output_file="$(mktemp)"
trap 'rm -f "${generated_file}" "${output_file}"' EXIT
{
  echo "<p align=\"center\">"
  echo "${build_rows}"
  echo "</p>"
  echo "<p align=\"center\"><sub>Auto-updated from latest repos via GitHub Actions.</sub></p>"
} >"${generated_file}"
if ! grep -q "${START_MARKER}" "${README_PATH}" || ! grep -q "${END_MARKER}" "${README_PATH}"; then
  echo "Markers not found in README.md. Aborting update." >&2
  exit 1
fi

output_file="$(mktemp)"
if ! grep -q "${START_MARKER}" "${README_PATH}" || ! grep -q "${END_MARKER}" "${README_PATH}"; then
  echo "Markers not found in ${README_PATH}; aborting update." >&2
  exit 1
fi

awk -v start="${START_MARKER}" -v end="${END_MARKER}" -v gen="${generated_file}" '
  $0 == start {
    print
    while ((getline line < gen) > 0) print line
    in_block = 1
    next
  }
  $0 == end {
    in_block = 0
    print
    next
  }
  !in_block { print }
' "${README_PATH}" > "${output_file}"

mv "${output_file}" "${README_PATH}"
rm -f "${generated_file}"
