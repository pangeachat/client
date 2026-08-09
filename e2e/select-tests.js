#!/usr/bin/env node

/**
 * Diff-based test selector for Pangea Chat E2E tests.
 *
 * Usage:
 *   node e2e/select-tests.js <git-ref> [--platform web|mobile|all]
 *
 * Examples:
 *   node e2e/select-tests.js origin/main
 *   node e2e/select-tests.js HEAD~1 --platform web
 *   node e2e/select-tests.js origin/main --platform mobile
 *
 * Outputs space-separated list of test file paths that should run based on changed files.
 */

const { execSync } = require("child_process");
const { minimatch } = require("minimatch");
const path = require("path");
const triggerMap = require("./trigger-map.json");

// Parse arguments
const args = process.argv.slice(2);
const platformIdx = args.indexOf("--platform");
const platform = platformIdx !== -1 ? args[platformIdx + 1] : "web";
const baseRef =
  args.find((a) => !a.startsWith("--") && a !== platform) || "origin/main";

if (!["web", "mobile", "all"].includes(platform)) {
  console.error("Invalid platform. Must be: web, mobile, or all");
  process.exit(1);
}

// Get changed files from git diff
let changedFiles;
try {
  changedFiles = execSync(`git diff ${baseRef} --name-only`, {
    encoding: "utf-8",
  })
    .trim()
    .split("\n")
    .filter(Boolean);
} catch (error) {
  console.error(`Error running git diff: ${error.message}`);
  process.exit(1);
}

// Always smoke-test login
const matched = new Set(["login"]);

for (const [script, entry] of Object.entries(triggerMap)) {
  if (changedFiles.some((f) => entry.globs.some((g) => minimatch(f, g)))) {
    matched.add(script);
  }
}

const testFiles = [...matched]
  .map((s) => {
    const entry = triggerMap[s];
    if (!entry) return null;
    if (platform === "mobile") return entry.mobile;
    if (platform === "web") return entry.web;
    return [entry.web, entry.mobile]; // "all"
  })
  .flat()
  .filter(Boolean);

process.stdout.write(testFiles.join(" "));
