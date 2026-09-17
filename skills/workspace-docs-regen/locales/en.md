## description
Regenerate the marked sections of meta-repo and package docs, and the workspace files, from workspace.yml and the package sources.

## report_regenerated_files
Regenerated {n} files.

## report_no_drift
No drift; all marker sections in canonical form.

## report_drift_detected
Drift detected in {n} file(s):

## error_malformed_markers
{n} file(s) have malformed markers; run with --repair to see the proposed fix. exit 2.

## error_validation
workspace.yml is invalid; the errors are listed above. exit 2.

## error_yq_missing
yq not on PATH (required by this toolkit). Install: brew install yq

## error_missing_workspace_yml
workspace.yml not found in this directory, its ancestors, or a *-meta directory beside one of them; cd into a repository of the workspace first.

## repair_prompt
Apply? (y/N)
