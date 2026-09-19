import assert from 'node:assert/strict';
import test from 'node:test';

import { resolveComparison, shouldRunMacOS } from './ci-change-classifier.mjs';

function fakeGit({ existing = [], changedPaths = [] } = {}) {
  return {
    commitExists: (sha) => existing.includes(sha),
    changedPaths: () => changedPaths,
  };
}

test('classifies normal pushes from their changed paths', () => {
  const event = { eventName: 'push', beforeSha: 'before', currentSha: 'current' };
  const docs = resolveComparison(event, fakeGit({ existing: ['before'], changedPaths: ['docs/development.md'] }));
  const source = resolveComparison(event, fakeGit({ existing: ['before'], changedPaths: ['App/App.swift'] }));

  assert.equal(shouldRunMacOS({ eventName: 'push', releaseEnabled: false, comparison: docs }), false);
  assert.equal(shouldRunMacOS({ eventName: 'push', releaseEnabled: false, comparison: source }), true);
});

test('runs full checks when the previous push commit is unavailable', () => {
  const comparison = resolveComparison(
    { eventName: 'push', beforeSha: 'missing', currentSha: 'current' },
    fakeGit(),
  );

  assert.equal(comparison.available, false);
  assert.match(comparison.reason, /missing is unavailable/);
  assert.equal(shouldRunMacOS({ eventName: 'push', releaseEnabled: false, comparison }), true);
});

test('runs full checks for first pushes with an all-zero before SHA', () => {
  const comparison = resolveComparison(
    { eventName: 'push', beforeSha: '0'.repeat(40), currentSha: 'current' },
    fakeGit(),
  );

  assert.equal(comparison.available, false);
  assert.match(comparison.reason, /no usable before commit/);
  assert.equal(shouldRunMacOS({ eventName: 'push', releaseEnabled: false, comparison }), true);
});

test('manual runs and enabled releases always run full checks', () => {
  const comparison = { available: true, changedPaths: ['README.md'], reason: null };
  assert.equal(shouldRunMacOS({ eventName: 'workflow_dispatch', releaseEnabled: false, comparison }), true);
  assert.equal(shouldRunMacOS({ eventName: 'push', releaseEnabled: true, comparison }), true);
});
