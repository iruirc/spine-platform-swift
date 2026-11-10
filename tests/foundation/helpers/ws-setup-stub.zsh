#!/usr/bin/env zsh
# Stand-ins for what the drivers cannot run: spine-toolkit:setup writing the root config, and the
# `## Stack` spelling swift-init hands it (agents/swift-init.md, "Flag values in `## Stack`").
# NOT shipped to users — testing only. The config carries only what the suite reads, so it cannot
# grow back into a copy of core's template.

# The `## Stack` value of one swift-init flag value; empty when the catalog has none.
wsstub::axis_value() {
  case "$1=$2" in
    UI=swiftui) print SwiftUI ;;
    UI=uikit) print UIKit ;;
    UI=appkit) print AppKit ;;
    Async=async-await) print async/await ;;
    Async=combine) print Combine ;;
    Async=rxswift) print RxSwift ;;
    DI=swinject) print Swinject ;;
    DI=factory) print Factory ;;
    DI=manual-factory|DI=plain) print manual ;;
    Architecture=mvvm|Architecture=mvvm-coordinator) print MVVM ;;
    Architecture=mvi) print MVI ;;
    Architecture=tca) print TCA ;;
    Architecture=viper) print VIPER ;;
    Architecture=clean) print Clean Architecture ;;
    Architecture=mvc) print MVC ;;
    Tests=swift-testing) print Swift Testing ;;
    Tests=xctest) print XCTest ;;
    Tests=quick-nimble) print Quick+Nimble ;;
  esac
}

# The Baseline value of an iOS floor, a macOS floor, or both (either may be empty).
wsstub::baseline() {
  local ios="$1" macos="$2"
  if [[ -n "$ios" && -n "$macos" ]]; then print iOS+macOS; return; fi
  if [[ -n "$ios" ]]; then
    (( ${ios%%.*} >= 17 )) && { print "iOS 17+"; return; }
    (( ${ios%%.*} == 16 )) && print "iOS 16+"
    return 0
  fi
  if [[ -n "$macos" ]]; then
    (( ${macos%%.*} >= 14 )) && { print "macOS 14+"; return; }
    (( ${macos%%.*} == 13 )) && print "macOS 13+"
  fi
  return 0
}

# spine-toolkit:setup run in <root>: SPINE.md with the answers and one `- <Axis>: <value>` line per
# Axis=value argument, and AGENTS.md. CLAUDE.md is already there from s02, and setup leaves it.
wsstub::setup() {
  local root="$1" lang="$2" mode="$3" progress="$4" av
  shift 4
  {
    cat <<EOF
# SPINE.md — Toolkit Configuration

## Project settings

[LANG] = [$lang]
[PROGRESS] = [$progress]

## Task defaults

[WORKFLOW_MODE] = [$mode]

## Platform

spine-platform-swift

## Stack

EOF
    for av in "$@"; do print -r -- "- ${av%%=*}: ${av#*=}"; done
  } > "$root/SPINE.md"
  [[ -f "$root/AGENTS.md" ]] || print -r -- "Read SPINE.md before working in this folder." > "$root/AGENTS.md"
}
