# SPINE.md — Toolkit Configuration

## Project settings

[LANG] = [en]
[PROGRESS] = [normal]

## Task defaults

[WORKFLOW_MODE] = [manual]

## Platform

spine-platform-swift

## Stack

- Baseline: iOS+macOS
- Tests: Swift Testing

## Workspace meta

<!-- WORKSPACE_META_BEGIN -->
- Workspace: RegenWS; launch agents from this folder
- sharedPackages/AKit — api-contract package
- sharedPackages/BEngine — engine package
- domainPackages/CFeature — feature package
- Before editing inside a repository, read its CLAUDE.md when it has one; commit in each repository separately
<!-- WORKSPACE_META_END -->

## Paths

- External packages: /sharedPackages/*
- External packages: /domainPackages/*
- Roots: /Tasks
- Roots: /Docs
