import assert from 'node:assert/strict';
import test from 'node:test';

import {
  referencedLocalizationKeys,
  validateCatalog,
  validateCatalogSource,
} from './validate-localizations.mjs';

function translated(value) {
  return { stringUnit: { state: 'translated', value } };
}

function catalog(localizations) {
  return { sourceLanguage: 'en', strings: { 'settings.language.title': { localizations } } };
}

test('accepts a catalog with all required translated string units', () => {
  const errors = validateCatalog(catalog({
    en: translated('Application language'),
    'zh-Hans': translated('应用语言'),
    'zh-Hant': translated('應用程式語言'),
  }), 'App/Localizable.xcstrings');

  assert.deepEqual(errors, []);
});

test('reports a missing required language for the affected key', () => {
  const errors = validateCatalog(catalog({
    en: translated('Application language'),
    'zh-Hans': translated('应用语言'),
  }), 'App/Localizable.xcstrings');

  assert.deepEqual(errors, [
    'App/Localizable.xcstrings: "settings.language.title" is missing zh-Hant.',
  ]);
});

test('rejects stale and empty translations', () => {
  const errors = validateCatalog(catalog({
    en: { stringUnit: { state: 'stale', value: 'Application language' } },
    'zh-Hans': translated('   '),
    'zh-Hant': translated('應用程式語言'),
  }), 'App/Localizable.xcstrings');

  assert.deepEqual(errors, [
    'App/Localizable.xcstrings: "settings.language.title" (en) must contain a non-empty translated stringUnit.',
    'App/Localizable.xcstrings: "settings.language.title" (zh-Hans) must contain a non-empty translated stringUnit.',
  ]);
});

test('reports malformed catalog source', () => {
  assert.deepEqual(
    validateCatalogSource('{', 'App/InfoPlist.xcstrings'),
    ['App/InfoPlist.xcstrings: invalid JSON.'],
  );
});

test('rejects translations that change format specifiers', () => {
  const errors = validateCatalog(catalog({
    en: translated('Version %@ (%lld)'),
    'zh-Hans': translated('版本 %@（%d）'),
    'zh-Hant': translated('版本 %@（%lld）'),
  }), 'App/Localizable.xcstrings');

  assert.deepEqual(errors, [
    'App/Localizable.xcstrings: "settings.language.title" (zh-Hans) must preserve format specifiers ["%@","%lld"].',
  ]);
});

test('extracts localization helper and SwiftUI literal keys from Swift source', () => {
  assert.deepEqual(
    referencedLocalizationKeys(`
      AppLocalized("settings.language.title")
      AppLocalizedFormat("error.project.path_not_found", path)
      Text("About")
      Text("\\(userInput)")
    `),
    ['settings.language.title', 'error.project.path_not_found', 'About'],
  );
});
