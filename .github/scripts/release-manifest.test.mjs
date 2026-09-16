import assert from 'node:assert/strict';
import test from 'node:test';

import {
  compareVersions,
  createReleasePlan,
  extractChangelogSection,
  parseManifest,
  parseVersion,
  validateReleaseOrder,
} from './release-manifest.mjs';

const changelog = `# Changelog

## [Unreleased]

## [0.2.0-beta.1] - 2026-09-15

### Added

- Added release automation.

## [0.2.0-alpha.2] - 2026-09-14

### Fixed

- Fixed an earlier build.
`;

test('accepts stable, alpha, and beta release versions', () => {
  assert.equal(parseVersion('1.2.3').channel, 'stable');
  assert.equal(parseVersion('1.2.3-alpha.1').base, '1.2.3');
  assert.equal(parseVersion('1.2.3-beta.12').prerelease, true);
});

test('rejects unsupported release version forms', () => {
  for (const version of ['1.2', 'v1.2.3', '01.2.3', '1.2.3-alpha', '1.2.3-beta.0', 'dev-1.2.3']) {
    assert.throws(() => parseVersion(version));
  }
});

test('requires exactly the version and release manifest fields', () => {
  assert.deepEqual(parseManifest('{"version":"1.2.3","release":false}').release, false);
  assert.throws(() => parseManifest('{"version":"1.2.3"}'));
  assert.throws(() => parseManifest('{"version":"1.2.3","release":"true"}'));
  assert.throws(() => parseManifest('{"version":"1.2.3","release":true,"channel":"stable"}'));
});

test('extracts only the exact non-empty changelog section', () => {
  assert.equal(
    extractChangelogSection(changelog, '0.2.0-beta.1'),
    '### Added\n\n- Added release automation.',
  );
  assert.throws(() => extractChangelogSection(changelog, '0.2.0-beta.2'));
  assert.throws(() => extractChangelogSection('## [1.0.0] - 2026-02-30\n\n- Invalid date.', '1.0.0'));
  assert.throws(() => extractChangelogSection('## [1.0.0] - 2026-02-20\n\n## [1.1.0] - 2026-02-21', '1.0.0'));
  assert.throws(() => extractChangelogSection([
    '## [1.0.0] - 2026-02-20',
    '',
    '- First.',
    '',
    '## [1.0.0] - 2026-02-21',
    '',
    '- Duplicate.',
  ].join('\n'), '1.0.0'));
});

test('orders alpha, beta, stable, and subsequent base versions', () => {
  assert.equal(compareVersions('1.0.0-alpha.1', '1.0.0-alpha.2'), -1);
  assert.equal(compareVersions('1.0.0-alpha.2', '1.0.0-beta.1'), -1);
  assert.equal(compareVersions('1.0.0-beta.2', '1.0.0'), -1);
  assert.equal(compareVersions('1.0.0', '1.1.0-alpha.1'), -1);
});

test('rejects versions that do not advance published history', () => {
  assert.doesNotThrow(() => validateReleaseOrder(parseVersion('1.1.0-alpha.1'), ['v1.0.0']));
  assert.throws(() => validateReleaseOrder(parseVersion('1.0.0-beta.2'), ['v1.0.0']));
  assert.throws(() => validateReleaseOrder(parseVersion('1.0.0'), ['v1.0.0']));
});

test('does not require release notes while release is disabled', () => {
  const plan = createReleasePlan({
    manifestSource: '{"version":"0.2.0-beta.1","release":false}',
    changelogSource: '',
    publishedTags: [],
  });
  assert.equal(plan.release, false);
});

test('requires matching notes and advancing history when release is enabled', () => {
  const plan = createReleasePlan({
    manifestSource: '{"version":"0.2.0-beta.1","release":true}',
    changelogSource: changelog,
    publishedTags: ['v0.2.0-alpha.2'],
  });
  assert.equal(plan.release, true);
  assert.throws(() => createReleasePlan({
    manifestSource: '{"version":"0.2.0-beta.1","release":true}',
    changelogSource: changelog,
    publishedTags: ['v0.2.0'],
  }));
});
