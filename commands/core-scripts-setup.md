---
description: Scaffold run.sh + release.sh + auto-update infrastructure (GitHub Release) for the current project — any language
argument-hint: [app-name] [owner/repo]
---

Invoke the `core-scripts-setup` skill and follow its procedure exactly (survey → settle the
parameters → version → run.sh → release.sh → update infrastructure → verify → report).

Arguments (may be empty): $ARGUMENTS — app name, `owner/repo`. Infer whatever is missing from
the repo itself.
