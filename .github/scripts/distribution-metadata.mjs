import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { compareVersions, parseVersion } from './release-manifest.mjs';

const SHA256_PATTERN = /^[0-9a-f]{64}$/;

function caskToken(version) {
  switch (version.channel) {
  case 'stable': return 'techne';
  case 'beta': return 'techne@beta';
  case 'alpha': return 'techne@alpha';
  default: throw new Error(`Unsupported Homebrew channel: ${version.channel}.`);
  }
}

export function renderCask(versionValue, sha256) {
  const version = parseVersion(versionValue);
  if (!SHA256_PATTERN.test(sha256)) {
    throw new Error('DMG_SHA256 must be a lowercase SHA-256 digest.');
  }

  return `cask "${caskToken(version)}" do
  version "${version.value}"
  sha256 "${sha256}"

  url "https://github.com/SlippinDylan/Techne/releases/download/v#{version}/Techne-#{version}.dmg"
  name "Techne"
  desc "Native macOS workspace for local development services and deployments"
  homepage "https://github.com/SlippinDylan/Techne"

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Techne.app"
end
`;
}

export function validateCaskAdvance(source, versionValue) {
  const match = /^\s*version\s+"([^"]+)"\s*$/m.exec(source);
  if (!match) throw new Error('Existing Cask must contain one literal version stanza.');

  const comparison = compareVersions(versionValue, match[1]);
  if (comparison < 0) {
    throw new Error(`Refusing to downgrade Cask from ${match[1]} to ${versionValue}.`);
  }
  return comparison === 0 ? 'current' : 'advance';
}

function itemVersion(item) {
  const matches = [...item.matchAll(/<sparkle:shortVersionString>([^<]+)<\/sparkle:shortVersionString>/g)];
  if (matches.length !== 1) throw new Error('Each appcast item must contain one short version.');
  return matches[0][1];
}

function itemChannel(item) {
  const matches = [...item.matchAll(/<sparkle:channel>([^<]+)<\/sparkle:channel>/g)];
  if (matches.length > 1) throw new Error('Each appcast item may contain at most one channel.');
  return matches[0]?.[1] ?? 'stable';
}

export function planAppcastUpdate(source, versionValue, channel, dmgName) {
  const version = parseVersion(versionValue);
  if (version.channel !== channel) {
    throw new Error(`Release version ${versionValue} does not match channel ${channel}.`);
  }

  const versions = [...source.matchAll(/<item(?:\s[^>]*)?>[\s\S]*?<\/item>/g)]
    .map((match) => ({ item: match[0], version: itemVersion(match[0]), channel: itemChannel(match[0]) }))
    .filter((item) => item.channel === channel)
    .map((item) => parseVersion(item.version));
  const newest = versions.sort((left, right) => compareVersions(right, left))[0];
  if (!newest) return 'append';

  const comparison = compareVersions(version, newest);
  if (comparison < 0) {
    throw new Error(`Refusing to downgrade ${channel} appcast from ${newest.value} to ${versionValue}.`);
  }
  if (comparison > 0) return 'append';

  const matchingItems = [...source.matchAll(/<item(?:\s[^>]*)?>[\s\S]*?<\/item>/g)]
    .filter((match) => itemChannel(match[0]) === channel && match[0].includes(dmgName));
  if (matchingItems.length !== 1) {
    throw new Error(`Current ${channel} appcast version ${versionValue} must contain exactly one ${dmgName} item.`);
  }
  return 'current';
}

export function updateAppcastDisplayVersion(source, versionValue, dmgName) {
  const version = parseVersion(versionValue);
  const items = [...source.matchAll(/<item(?:\s[^>]*)?>[\s\S]*?<\/item>/g)];
  const matches = items.filter((match) => match[0].includes(dmgName));
  if (matches.length !== 1) {
    throw new Error(`appcast must contain exactly one item for ${dmgName}.`);
  }

  const item = matches[0];
  const shortVersionPattern = /<sparkle:shortVersionString>[^<]*<\/sparkle:shortVersionString>/g;
  if ([...item[0].matchAll(shortVersionPattern)].length !== 1) {
    throw new Error(`appcast item for ${dmgName} must contain one short version.`);
  }

  const updatedItem = item[0].replace(
    shortVersionPattern,
    `<sparkle:shortVersionString>${version.value}</sparkle:shortVersionString>`,
  );
  return `${source.slice(0, item.index)}${updatedItem}${source.slice(item.index + item[0].length)}`;
}

async function main() {
  const command = process.argv[2];
  const version = process.env.VERSION ?? '';

  if (command === 'cask') {
    const existingCaskPath = process.env.EXISTING_CASK_PATH;
    if (existingCaskPath) {
      const existingCask = await readFile(existingCaskPath, 'utf8');
      if (validateCaskAdvance(existingCask, version) === 'current') {
        process.stdout.write(existingCask);
        return;
      }
    }
    process.stdout.write(renderCask(version, process.env.DMG_SHA256 ?? ''));
    return;
  }

  if (command === 'appcast-plan') {
    const path = process.argv[3];
    if (!path) throw new Error('appcast-plan command requires an appcast path.');
    process.stdout.write(`${planAppcastUpdate(
      await readFile(path, 'utf8'),
      version,
      process.env.CHANNEL ?? '',
      process.env.DMG_NAME ?? '',
    )}\n`);
    return;
  }

  if (command === 'appcast') {
    const path = process.argv[3];
    if (!path) throw new Error('appcast command requires an appcast path.');
    await writeFile(path, updateAppcastDisplayVersion(
      await readFile(path, 'utf8'),
      version,
      process.env.DMG_NAME ?? '',
    ), 'utf8');
    return;
  }

  throw new Error(`Unknown command: ${command ?? ''}.`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  main().catch((error) => {
    console.error(`::error::Distribution metadata failed: ${error.message}`);
    process.exitCode = 1;
  });
}
