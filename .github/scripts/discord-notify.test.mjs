import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildDiscordPayload,
  buildNotification,
  escapeDiscordMarkdown,
  extractReleaseHighlights,
  sendDiscordNotification,
  truncate,
} from './discord-notify.mjs';

const repository = { full_name: 'owner/Techne' };
const sender = { login: 'developer' };

test('normalizes text and escapes Discord Markdown', () => {
  assert.equal(truncate('line one\nline two', 30), 'line one line two');
  assert.equal(truncate('A'.repeat(10), 5), 'AAAA…');
  assert.equal(escapeDiscordMarkdown('*bold* [link](url) > quote'), '\\*bold\\* \\[link\\]\\(url\\) \\> quote');
});

test('builds a single embed with a primary URL, action links, colors, and disabled mentions', () => {
  const sha = 'a'.repeat(40);
  const notification = buildNotification('push', {
    repository,
    sender,
    ref: 'refs/heads/main',
    after: sha,
    size: 2,
    commits: [{ id: sha }],
    head_commit: { message: '*release* [notes](https://example.test)' },
  });
  const payload = buildDiscordPayload(notification);
  const embed = payload.embeds[0];

  assert.equal(payload.username, 'Techne');
  assert.deepEqual(payload.allowed_mentions, { parse: [] });
  assert.equal(payload.embeds.length, 1);
  assert.equal(embed.color, 0x5865F2);
  assert.equal(embed.url, `https://github.com/owner/Techne/commit/${sha}`);
  assert.ok(embed.description.includes('\\*release\\* \\[notes\\]\\(https://example.test\\)'));
  assert.match(embed.description, /\[查看提交\]\(https:\/\/github\.com\/owner\/Techne\/commit\//);
});

test('normalizes every configured collaboration event', () => {
  const cases = [
    ['pull_request_target', {
      repository,
      sender,
      action: 'opened',
      pull_request: { number: 1, title: 'PR', html_url: 'https://github.com/owner/Techne/pull/1' },
    }],
    ['issues', {
      repository,
      sender,
      action: 'opened',
      issue: { number: 2, title: 'Issue', html_url: 'https://github.com/owner/Techne/issues/2' },
    }],
    ['issue_comment', {
      repository,
      sender,
      issue: { number: 2, title: 'Issue' },
      comment: { body: 'Comment', html_url: 'https://github.com/owner/Techne/issues/2#issuecomment-1' },
    }],
    ['pull_request_review', {
      repository,
      sender,
      pull_request: { number: 3, title: 'PR', html_url: 'https://github.com/owner/Techne/pull/3' },
      review: { state: 'approved' },
    }],
  ];

  for (const [eventName, event] of cases) {
    const notification = buildNotification(eventName, event);
    assert.match(notification.title, /^Techne /);
    assert.ok(notification.button.url);
  }

  const untrusted = buildNotification('issue_comment', {
    repository,
    sender,
    issue: { number: 2, title: '<@everyone>' },
    comment: { body: '**unsafe**', html_url: 'https://example.com/steal' },
  });
  const payload = buildDiscordPayload(untrusted);
  assert.equal(payload.embeds[0].url, 'https://github.com/owner/Techne');
  assert.match(payload.embeds[0].description, /\\<@everyone\\>/);
});

test('keeps event filters and result colors', () => {
  assert.equal(buildNotification('workflow_run', {
    repository,
    workflow_run: { name: 'CI', conclusion: 'success', event: 'push', head_branch: 'feature' },
  }), null);
  assert.equal(buildNotification('workflow_run', {
    repository,
    workflow_run: { name: 'Release', conclusion: 'success', event: 'workflow_run', head_branch: 'main' },
  }), null);
  const review = buildNotification('pull_request_review', {
    repository,
    sender,
    pull_request: { number: 3, title: 'PR', html_url: 'https://github.com/owner/Techne/pull/3' },
    review: { state: 'changes_requested' },
  });
  assert.equal(buildDiscordPayload(review).embeds[0].color, 0xED4245);
});

test('builds release and packaging notifications with Techne fields', () => {
  const release = buildNotification('release', {
    repository,
    sender,
    release: {
      tag_name: 'v0.1.0-beta.1',
      prerelease: true,
      html_url: 'https://github.com/owner/Techne/releases/tag/v0.1.0-beta.1',
      body: '- Added automation.',
      assets: [{
        name: 'Techne-0.1.0-beta.1.dmg',
        browser_download_url: 'https://github.com/owner/Techne/releases/download/v0.1.0-beta.1/Techne-0.1.0-beta.1.dmg',
      }],
    },
  });
  const releaseEmbed = buildDiscordPayload(release).embeds[0];
  assert.equal(releaseEmbed.color, 0x57F287);
  assert.match(releaseEmbed.description, /架构：arm64/);
  assert.match(releaseEmbed.description, /签名：Apple Development（未公证）/);
  assert.match(releaseEmbed.description, /\[下载 DMG\]/);

  const started = buildNotification('repository_dispatch', {
    repository,
    sender,
    action: 'release_started',
    client_payload: {
      version: '0.1.0-beta.1',
      prerelease: true,
      dmg_name: 'Techne-0.1.0-beta.1.dmg',
      sha: 'a'.repeat(40),
      run_url: 'https://github.com/owner/Techne/actions/runs/12',
    },
  });
  assert.equal(started.title, 'Techne 0.1.0-beta.1 开始打包');
  assert.equal(buildDiscordPayload(started).embeds[0].color, 0x5865F2);
});

test('extracts at most three release highlights', () => {
  assert.deepEqual(extractReleaseHighlights('- One\n- Two\nText\n* Three\n- Four'), [
    '• One',
    '• Two',
    '• Three',
  ]);
});

test('accepts every 2xx response and preserves existing webhook parameters while setting wait=true', async () => {
  let request;
  await sendDiscordNotification({ test: true }, 'https://discord.example/webhook?token=secret&thread_id=42', {
    fetchImplementation: async (url, options) => {
      request = { url, options };
      return { ok: true, status: 204 };
    },
  });

  const endpoint = new URL(request.url);
  assert.equal(endpoint.searchParams.get('token'), 'secret');
  assert.equal(endpoint.searchParams.get('thread_id'), '42');
  assert.equal(endpoint.searchParams.get('wait'), 'true');
  assert.ok(request.options.signal instanceof AbortSignal);
});

test('retries Discord rate limits using Retry-After and retry_after seconds', async () => {
  const waits = [];
  let attempts = 0;
  await sendDiscordNotification({}, 'https://discord.example/webhook', {
    fetchImplementation: async () => {
      attempts += 1;
      if (attempts === 1) {
        return {
          ok: false,
          status: 429,
          headers: { get: () => '0.5' },
          json: async () => ({ retry_after: 1.5 }),
        };
      }
      return { ok: true, status: 200 };
    },
    wait: async (milliseconds) => { waits.push(milliseconds); },
  });
  assert.equal(attempts, 2);
  assert.deepEqual(waits, [500]);

  attempts = 0;
  waits.length = 0;
  await sendDiscordNotification({}, 'https://discord.example/webhook', {
    fetchImplementation: async () => {
      attempts += 1;
      if (attempts === 1) {
        return {
          ok: false,
          status: 429,
          headers: { get: () => null },
          json: async () => ({ retry_after: 1.5 }),
        };
      }
      return { ok: true, status: 200 };
    },
    wait: async (milliseconds) => { waits.push(milliseconds); },
  });
  assert.equal(attempts, 2);
  assert.deepEqual(waits, [1_500]);
});

test('retries 5xx responses with exponential backoff but not 4xx responses', async () => {
  const waits = [];
  let attempts = 0;
  await sendDiscordNotification({}, 'https://discord.example/webhook', {
    fetchImplementation: async () => {
      attempts += 1;
      return attempts === 1 ? { ok: false, status: 503 } : { ok: true, status: 202 };
    },
    wait: async (milliseconds) => { waits.push(milliseconds); },
  });
  assert.equal(attempts, 2);
  assert.deepEqual(waits, [250]);

  attempts = 0;
  await assert.rejects(sendDiscordNotification({}, 'https://discord.example/webhook', {
    fetchImplementation: async () => {
      attempts += 1;
      return { ok: false, status: 400 };
    },
    wait: async () => { throw new Error('4xx must not retry'); },
  }), /HTTP 400/);
  assert.equal(attempts, 1);
});

test('retries transient network failures', async () => {
  const waits = [];
  let attempts = 0;
  await sendDiscordNotification({}, 'https://discord.example/webhook', {
    fetchImplementation: async () => {
      attempts += 1;
      if (attempts === 1) throw new Error('network');
      return { ok: true, status: 204 };
    },
    wait: async (milliseconds) => { waits.push(milliseconds); },
  });
  assert.equal(attempts, 2);
  assert.deepEqual(waits, [250]);
});

test('rejects an invalid webhook URL without echoing its value', async () => {
  const invalidWebhook = 'not-a-url-with-secret-token';
  await assert.rejects(
    sendDiscordNotification({}, invalidWebhook),
    (error) => error.message === 'DISCORD_WEBHOOK_URL is invalid.' && !error.message.includes(invalidWebhook),
  );
});
