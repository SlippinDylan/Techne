import { appendFile, readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const MANIFEST_PATH = 'Config/Release/manifest.json';
const CHANGELOG_PATH = 'CHANGELOG.md';
const VERSION_PATTERN = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-(alpha|beta)\.([1-9]\d*))?$/;

export function parseVersion(value) {
  const version = String(value ?? '');
  const match = VERSION_PATTERN.exec(version);

  if (!match) {
    throw new Error('version must match x.y.z, x.y.z-alpha.n, or x.y.z-beta.n.');
  }

  const [, major, minor, patch, channel, sequence] = match;
  const numbers = [Number(major), Number(minor), Number(patch)];
  if (!numbers.every(Number.isSafeInteger) || (sequence && !Number.isSafeInteger(Number(sequence)))) {
    throw new Error('version components must be safe integers.');
  }

  return {
    value: version,
    base: `${major}.${minor}.${patch}`,
    numbers,
    channel: channel ?? 'stable',
    sequence: sequence ? Number(sequence) : null,
    prerelease: channel !== undefined,
  };
}

export function parseManifest(source) {
  let manifest;

  try {
    manifest = JSON.parse(source);
  } catch {
    throw new Error(`${MANIFEST_PATH} must contain valid JSON.`);
  }

  if (!manifest || Array.isArray(manifest) || typeof manifest !== 'object') {
    throw new Error(`${MANIFEST_PATH} must contain a JSON object.`);
  }

  const keys = Object.keys(manifest).sort();
  if (keys.join(',') !== 'release,version') {
    throw new Error(`${MANIFEST_PATH} must contain exactly "version" and "release".`);
  }

  if (typeof manifest.release !== 'boolean') {
    throw new Error('release must be a boolean.');
  }

  return { version: parseVersion(manifest.version), release: manifest.release };
}

function parseDate(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) {
    throw new Error('CHANGELOG release dates must use YYYY-MM-DD.');
  }

  const [, year, month, day] = match;
  const date = new Date(Date.UTC(Number(year), Number(month) - 1, Number(day)));
  if (date.toISOString().slice(0, 10) !== value) {
    throw new Error(`CHANGELOG release date is invalid: ${value}.`);
  }
}

export function extractChangelogSection(source, version) {
  const headingPattern = /^## \[([^\]]+)] - (\d{4}-\d{2}-\d{2})$/gm;
  const headings = [...source.matchAll(headingPattern)];
  const matches = headings.filter((heading) => heading[1] === version);

  if (matches.length !== 1) {
    throw new Error(`CHANGELOG.md must contain exactly one "## [${version}] - YYYY-MM-DD" heading.`);
  }

  const heading = matches[0];
  parseDate(heading[2]);
  const bodyStart = heading.index + heading[0].length;
  const nextHeading = /^## /gm;
  nextHeading.lastIndex = bodyStart;
  const following = nextHeading.exec(source);
  const body = source.slice(bodyStart, following?.index ?? source.length).trim();

  if (!body) {
    throw new Error(`CHANGELOG.md section ${version} must not be empty.`);
  }

  return body;
}

function stageRank(version) {
  if (version.channel === 'alpha') return 0;
  if (version.channel === 'beta') return 1;
  return 2;
}

export function compareVersions(leftValue, rightValue) {
  const left = typeof leftValue === 'string' ? parseVersion(leftValue) : leftValue;
  const right = typeof rightValue === 'string' ? parseVersion(rightValue) : rightValue;

  for (let index = 0; index < left.numbers.length; index += 1) {
    if (left.numbers[index] !== right.numbers[index]) {
      return Math.sign(left.numbers[index] - right.numbers[index]);
    }
  }

  if (stageRank(left) !== stageRank(right)) {
    return Math.sign(stageRank(left) - stageRank(right));
  }

  return Math.sign((left.sequence ?? 0) - (right.sequence ?? 0));
}

export function validateReleaseOrder(version, publishedTags) {
  const published = publishedTags
    .map((tag) => tag.replace(/^v/, ''))
    .filter((tag) => VERSION_PATTERN.test(tag))
    .map(parseVersion);

  const newest = published.sort((left, right) => compareVersions(right, left))[0];
  if (newest && compareVersions(version, newest) <= 0) {
    throw new Error(`version ${version.value} must be newer than published version ${newest.value}.`);
  }
}

export function createReleasePlan({ manifestSource, changelogSource, publishedTags = [] }) {
  const manifest = parseManifest(manifestSource);
  if (!manifest.release) {
    return { release: false, version: manifest.version };
  }

  extractChangelogSection(changelogSource, manifest.version.value);
  validateReleaseOrder(manifest.version, publishedTags);
  return { release: true, version: manifest.version };
}

async function writeOutputs(values) {
  const outputPath = process.env.GITHUB_OUTPUT;
  if (!outputPath) return;

  const lines = Object.entries(values).map(([key, value]) => `${key}=${String(value)}\n`).join('');
  await appendFile(outputPath, lines, 'utf8');
}

async function loadInputs() {
  const [manifestSource, changelogSource] = await Promise.all([
    readFile(MANIFEST_PATH, 'utf8'),
    readFile(CHANGELOG_PATH, 'utf8'),
  ]);
  return { manifestSource, changelogSource };
}

async function main() {
  const command = process.argv[2] ?? 'validate';
  const inputs = await loadInputs();

  if (command === 'notes') {
    const manifest = parseManifest(inputs.manifestSource);
    process.stdout.write(`${extractChangelogSection(inputs.changelogSource, manifest.version.value)}\n`);
    return;
  }

  if (command === 'validate') {
    const manifest = parseManifest(inputs.manifestSource);
    await writeOutputs({
      release: manifest.release,
      version: manifest.version.value,
      marketing_version: manifest.version.base,
      channel: manifest.version.channel,
      tag: `v${manifest.version.value}`,
      prerelease: manifest.version.prerelease,
      dmg_name: `Techne-${manifest.version.value}.dmg`,
    });
    return;
  }

  if (command === 'plan') {
    const publishedTags = String(process.env.PUBLISHED_RELEASE_TAGS ?? '').split('\n').filter(Boolean);
    const plan = createReleasePlan({ ...inputs, publishedTags });
    await writeOutputs({ publish: plan.release });
    return;
  }

  throw new Error(`Unknown command: ${command}.`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  main().catch((error) => {
    console.error(`::error::Release manifest validation failed: ${error.message}`);
    process.exitCode = 1;
  });
}
