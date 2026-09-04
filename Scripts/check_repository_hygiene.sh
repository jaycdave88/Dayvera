#!/usr/bin/env bash

set -euo pipefail

forbidden_paths='(^|/)(\.env($|\.)|[^/]+\.(p8|p12|pem|key|pfx|cer|crt|der|jks|keystore|mobileprovision|provisionprofile|ipa|xcarchive|dSYM|xcresult|xccovarchive|xccovreport|profdata|sqlite|storedata)($|/)|HealthExport($|/)|export\.xml$|\.zvec-grep($|/)|LocalSigning\.xcconfig$|Secrets\.(xcconfig|plist|json)$|[^/]+\.local\.xcconfig$|[^/]+\.(secret|secrets)\.(xcconfig|plist|json)$)'
secret_pattern='BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY|github_pat_[A-Za-z0-9_]+|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|xox[baprs]-[0-9A-Za-z-]{10,}|sk-[A-Za-z0-9_-]{20,}|Bearer[[:space:]]+[A-Za-z0-9._~-]{20,}'
local_metadata_pattern='/Users/[^/[:space:]]+|DEVELOPMENT_TEAM = [A-Z0-9]{10};'

failed=0

if git ls-files | grep -E "$forbidden_paths"; then
    echo "Repository hygiene failed: a forbidden local or credential artifact is tracked." >&2
    failed=1
fi

if git rev-list --objects --all | sed -E 's/^[^ ]+ //' | grep -E "$forbidden_paths"; then
    echo "Repository hygiene failed: a forbidden artifact remains reachable in Git history." >&2
    failed=1
fi

if git grep -l -I -E "$secret_pattern" -- . \
    ':(exclude)SECURITY.md' \
    ':(exclude)Scripts/check_repository_hygiene.sh'; then
    echo "Repository hygiene failed: a high-confidence secret pattern was found." >&2
    failed=1
fi

if git grep -l -I -E "$local_metadata_pattern" -- . \
    ':(exclude)SECURITY.md' \
    ':(exclude)Scripts/check_repository_hygiene.sh'; then
    echo "Repository hygiene failed: machine-specific path or signing-team metadata was found." >&2
    failed=1
fi

while IFS= read -r commit; do
    if git grep -l -I -E "$secret_pattern|$local_metadata_pattern" "$commit" -- . \
        ':(exclude)SECURITY.md' \
        ':(exclude)Scripts/check_repository_hygiene.sh'; then
        echo "Repository hygiene failed: sensitive content was found in reachable Git history." >&2
        failed=1
        break
    fi
done < <(git rev-list --all)

if git rev-list --objects --all | grep -E ' \.zvec-grep/' >/dev/null; then
    echo "Repository hygiene failed: zvec-grep artifacts remain reachable in Git history." >&2
    failed=1
fi

if [[ "$failed" -ne 0 ]]; then
    exit 1
fi

echo "Repository hygiene checks passed."
