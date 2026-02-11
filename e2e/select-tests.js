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

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

// Parse arguments
const args = process.argv.slice(2);
if (args.length === 0) {
  console.error('Usage: node e2e/select-tests.js <git-ref> [--platform web|mobile|all]');
  process.exit(1);
}

const gitRef = args[0];
let platform = 'web'; // default

// Parse --platform flag
const platformIndex = args.indexOf('--platform');
if (platformIndex !== -1 && args[platformIndex + 1]) {
  platform = args[platformIndex + 1];
  if (!['web', 'mobile', 'all'].includes(platform)) {
    console.error('Invalid platform. Must be: web, mobile, or all');
    process.exit(1);
  }
}

// Read trigger map
const triggerMapPath = path.join(__dirname, 'trigger-map.json');
const triggerMap = JSON.parse(fs.readFileSync(triggerMapPath, 'utf8'));

// Get changed files from git diff
let changedFiles;
try {
  changedFiles = execSync(`git diff --name-only ${gitRef}`, { encoding: 'utf8' })
    .split('\n')
    .filter(Boolean);
} catch (error) {
  console.error(`Error running git diff: ${error.message}`);
  process.exit(1);
}

if (changedFiles.length === 0) {
  console.log(''); // No changed files, no tests to run
  process.exit(0);
}

// Match changed files against globs
const matchedTests = new Set();

for (const [scriptName, config] of Object.entries(triggerMap)) {
  const { globs, web, mobile } = config;
  
  // Check if any changed file matches any glob pattern
  const hasMatch = changedFiles.some(file => 
    globs.some(glob => {
      // Simple glob matching (** = any path, * = any characters in segment)
      const pattern = glob
        .replace(/\./g, '\\.')   // escape dots first
        .replace(/\*\*/g, '.*')  // ** matches any path
        .replace(/\*/g, '[^/]*'); // * matches any characters except /
      const regex = new RegExp(`^${pattern}$`);
      return regex.test(file);
    })
  );
  
  if (hasMatch) {
    // Add matching test files based on platform filter
    if ((platform === 'web' || platform === 'all') && web) {
      matchedTests.add(web);
    }
    if ((platform === 'mobile' || platform === 'all') && mobile) {
      matchedTests.add(mobile);
    }
  }
}

// Output space-separated list of test files
console.log(Array.from(matchedTests).join(' '));
