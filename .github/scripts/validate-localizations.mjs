import { readFile, readdir } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const CATALOG_PATHS = [
  'App/Localizable.xcstrings',
  'App/InfoPlist.xcstrings',
];
const REQUIRED_LANGUAGES = ['en', 'zh-Hans', 'zh-Hant'];

function translatedStringUnit(localization) {
  const stringUnit = localization?.stringUnit;
  return stringUnit
    && stringUnit.state === 'translated'
    && typeof stringUnit.value === 'string'
    && stringUnit.value.trim().length > 0;
}

function formatSpecifiers(value) {
  return [...value.matchAll(/%(?:\d+\$)?(?:lld|d|@)/g)].map((match) => match[0]);
}

export function validateCatalog(catalog, path) {
  if (!catalog || Array.isArray(catalog) || typeof catalog !== 'object') {
    return [`${path}: catalog root must be a JSON object.`];
  }

  if (!catalog.strings || Array.isArray(catalog.strings) || typeof catalog.strings !== 'object') {
    return [`${path}: missing strings object.`];
  }

  if (catalog.sourceLanguage !== 'en') {
    return [`${path}: sourceLanguage must be en.`];
  }

  if (Object.keys(catalog.strings).length === 0) {
    return [`${path}: strings must not be empty.`];
  }

  const errors = [];
  for (const [key, entry] of Object.entries(catalog.strings)) {
    const expectedSpecifiers = formatSpecifiers(entry?.localizations?.en?.stringUnit?.value ?? '');
    for (const language of REQUIRED_LANGUAGES) {
      const localization = entry?.localizations?.[language];
      if (!localization) {
        errors.push(`${path}: ${JSON.stringify(key)} is missing ${language}.`);
        continue;
      }

      if (!translatedStringUnit(localization)) {
        errors.push(
          `${path}: ${JSON.stringify(key)} (${language}) must contain a non-empty translated stringUnit.`,
        );
        continue;
      }

      const actualSpecifiers = formatSpecifiers(localization.stringUnit.value);
      if (actualSpecifiers.join(',') !== expectedSpecifiers.join(',')) {
        errors.push(
          `${path}: ${JSON.stringify(key)} (${language}) must preserve format specifiers `
          + `${JSON.stringify(expectedSpecifiers)}.`,
        );
      }
    }
  }
  return errors;
}

export function referencedLocalizationKeys(source) {
  const keys = new Set(
    [...source.matchAll(/AppLocalized(?:Format)?\("((?:\\.|[^"\\])+)"/g)]
      .map((match) => JSON.parse(`"${match[1]}"`)),
  );
  const directAPI = /(?:Text|Button|Label|Picker|TextField|navigationTitle|navigationSubtitle|help|alert|confirmationDialog)\("((?:\\.|[^"\\])*)"/g;
  for (const match of source.matchAll(directAPI)) {
    if (match[1].includes('\\(')) continue;
    const key = JSON.parse(`"${match[1]}"`);
    if (key) keys.add(key);
  }
  return [...keys];
}

async function swiftSources(directory) {
  const sources = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      sources.push(...await swiftSources(path));
    } else if (entry.name.endsWith('.swift')) {
      sources.push(path);
    }
  }
  return sources;
}

export function validateCatalogSource(source, path) {
  let catalog;
  try {
    catalog = JSON.parse(source);
  } catch {
    return [`${path}: invalid JSON.`];
  }
  return validateCatalog(catalog, path);
}

export async function validateLocalizationCatalogs(read = readFile) {
  const results = await Promise.all(CATALOG_PATHS.map(async (path) => {
    try {
      return validateCatalogSource(await read(path, 'utf8'), path);
    } catch (error) {
      return [`${path}: unable to read catalog: ${error.message}`];
    }
  }));
  const errors = results.flat();
  if (read !== readFile || errors.length > 0) return errors;

  const localizable = JSON.parse(await readFile(CATALOG_PATHS[0], 'utf8'));
  const referencedKeys = new Set();
  for (const path of await swiftSources('App')) {
    for (const key of referencedLocalizationKeys(await readFile(path, 'utf8'))) {
      referencedKeys.add(key);
    }
  }
  for (const key of referencedKeys) {
    if (!Object.hasOwn(localizable.strings, key)) {
      errors.push(`${CATALOG_PATHS[0]}: missing referenced key ${JSON.stringify(key)}.`);
    }
  }
  return errors;
}

async function main() {
  const errors = await validateLocalizationCatalogs();
  if (errors.length > 0) {
    throw new Error(errors.join('\n'));
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  main().catch((error) => {
    console.error(`::error::Localization validation failed:\n${error.message}`);
    process.exitCode = 1;
  });
}
