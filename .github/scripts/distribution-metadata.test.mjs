import assert from 'node:assert/strict';
import test from 'node:test';

import {
  planAppcastUpdate,
  renderCask,
  updateAppcastDisplayVersion,
  validateCaskAdvance,
} from './distribution-metadata.mjs';

const appcast = `<?xml version="1.0"?>
<rss><channel>
<item><sparkle:shortVersionString>0.1.0</sparkle:shortVersionString><enclosure url="Techne-0.1.0.dmg" /></item>
<item><sparkle:shortVersionString>0.2.0-beta.1</sparkle:shortVersionString><sparkle:channel>beta</sparkle:channel><enclosure url="Techne-0.2.0-beta.1.dmg" /></item>
</channel></rss>`;

test('renders channel-specific Casks for immutable GitHub Release DMGs', () => {
  const cask = renderCask('0.2.0-beta.1', 'a'.repeat(64));

  assert.match(cask, /^cask "techne@beta" do/m);
  assert.match(cask, /version "0\.2\.0-beta\.1"/);
  assert.match(cask, /sha256 "a{64}"/);
  assert.match(cask, /auto_updates true/);
  assert.match(cask, /depends_on arch: :arm64/);
  assert.match(cask, /depends_on macos: :tahoe/);
  assert.doesNotMatch(cask, /verified:/);
  assert.match(renderCask('1.0.0', 'b'.repeat(64)), /^cask "techne" do/m);
  assert.match(renderCask('1.0.0-alpha.1', 'c'.repeat(64)), /^cask "techne@alpha" do/m);
});

test('rejects malformed digests and Cask downgrades while retaining equal versions', () => {
  assert.throws(() => renderCask('1.0.0', 'not-a-digest'));
  const current = 'cask "techne@beta" do\n  version "0.2.0-beta.2"\nend\n';
  assert.equal(validateCaskAdvance(current, '0.2.0-beta.2'), 'current');
  assert.equal(validateCaskAdvance(current, '0.2.0-beta.3'), 'advance');
  assert.throws(() => validateCaskAdvance(current, '0.2.0-beta.1'));
});

test('allows only advancing appcast items for each channel and treats equal releases as idempotent', () => {
  assert.equal(planAppcastUpdate(appcast, '0.1.0', 'stable', 'Techne-0.1.0.dmg'), 'current');
  assert.equal(planAppcastUpdate(appcast, '0.1.1', 'stable', 'Techne-0.1.1.dmg'), 'append');
  assert.equal(planAppcastUpdate(appcast, '0.2.0-beta.2', 'beta', 'Techne-0.2.0-beta.2.dmg'), 'append');
  assert.throws(() => planAppcastUpdate(appcast, '0.0.9', 'stable', 'Techne-0.0.9.dmg'));
  assert.throws(() => planAppcastUpdate(appcast, '0.2.0-beta.1', 'stable', 'Techne-0.2.0-beta.1.dmg'));
  assert.throws(() => planAppcastUpdate(appcast, '0.1.0', 'stable', 'missing.dmg'));
});

test('updates only the matching appcast item display version', () => {
  const updated = updateAppcastDisplayVersion(appcast, '0.2.0-beta.1', 'Techne-0.2.0-beta.1.dmg');
  assert.match(updated, /<sparkle:shortVersionString>0\.1\.0<\/sparkle:shortVersionString>/);
  assert.match(updated, /<sparkle:shortVersionString>0\.2\.0-beta\.1<\/sparkle:shortVersionString>/);
});
