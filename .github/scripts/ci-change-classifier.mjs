import { spawnSync } from 'node:child_process';
import { appendFileSync, readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const ZERO_SHA_PATTERN = /^0+$/;

function isDocumentationPath(path) {
  return path === 'README.md'
    || path === 'LICENSE'
    || path === 'AGENTS.md'
    || path.startsWith('docs/');
}

function gitCommand(args) {
  const result = spawnSync('git', args, { encoding: null });
  if (result.status !== 0) {
    throw new Error(Buffer.from(result.stderr ?? '').toString('utf8').trim() || `git ${args[0]} failed`);
  }
  return Buffer.from(result.stdout ?? '');
}

const defaultGit = {
  commitExists(sha) {
    return spawnSync('git', ['cat-file', '-e', `${sha}^{commit}`], { stdio: 'ignore' }).status === 0;
  },
  changedPaths(revisions) {
    return gitCommand(['diff', '--name-only', '-z', ...revisions])
      .toString('utf8')
      .split('\0')
      .filter(Boolean);
  },
};

export function resolveComparison(event, git = defaultGit) {
  if (event.eventName === 'workflow_dispatch') {
    return { available: false, changedPaths: [], reason: null };
  }

  if (event.eventName === 'pull_request') {
    if (!event.baseSha || !event.headSha || !git.commitExists(event.baseSha) || !git.commitExists(event.headSha)) {
      return {
        available: false,
        changedPaths: [],
        reason: 'Pull request comparison commits are unavailable; running full macOS checks.',
      };
    }
    return { available: true, changedPaths: git.changedPaths([`${event.baseSha}...${event.headSha}`]), reason: null };
  }

  if (event.eventName === 'push') {
    if (!event.beforeSha || ZERO_SHA_PATTERN.test(event.beforeSha)) {
      return {
        available: false,
        changedPaths: [],
        reason: 'Push has no usable before commit; running full macOS checks.',
      };
    }
    if (!git.commitExists(event.beforeSha)) {
      return {
        available: false,
        changedPaths: [],
        reason: `Previous commit ${event.beforeSha} is unavailable; running full macOS checks.`,
      };
    }
    return { available: true, changedPaths: git.changedPaths([event.beforeSha, event.currentSha]), reason: null };
  }

  return {
    available: false,
    changedPaths: [],
    reason: `Unsupported event ${event.eventName || 'unknown'}; running full macOS checks.`,
  };
}

export function shouldRunMacOS({ eventName, releaseEnabled, comparison }) {
  if (eventName === 'workflow_dispatch' || !comparison.available || releaseEnabled) return true;
  return comparison.changedPaths.some((path) => !isDocumentationPath(path));
}

function main() {
  const event = {
    eventName: process.env.EVENT_NAME ?? '',
    beforeSha: process.env.BEFORE_SHA ?? '',
    currentSha: process.env.CURRENT_SHA ?? '',
    baseSha: process.env.BASE_SHA ?? '',
    headSha: process.env.HEAD_SHA ?? '',
  };
  const manifest = JSON.parse(readFileSync('Config/Release/manifest.json', 'utf8'));
  const comparison = resolveComparison(event);
  if (comparison.reason) console.log(`::warning::${comparison.reason}`);

  const outputPath = process.env.GITHUB_OUTPUT;
  if (!outputPath) throw new Error('GITHUB_OUTPUT is required.');
  const runMacOS = shouldRunMacOS({
    eventName: event.eventName,
    releaseEnabled: manifest.release === true,
    comparison,
  });
  appendFileSync(outputPath, `run_macos=${runMacOS}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
