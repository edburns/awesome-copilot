import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const self = fileURLToPath(import.meta.url);
const plugin = path.resolve(path.dirname(self), '..');
const skillName = 'shepherd-task-30-from-assignment-to-ready';
const skill = path.resolve(plugin, '../../skills', skillName);
const sha = 'a'.repeat(40);
const newSha = 'b'.repeat(40);
const quote = text => `'${text.replaceAll("'", "'\\''")}'`;
const boundary = '2026-10-02T12:00:00Z';
const event = (id, kind, date = boundary, app = 'copilot-swe-agent') => ({
  id, event: `copilot_work_${kind}`, created_at: date, performed_via_github_app: { slug: app },
});
const old = [event(1, 'started', '2026-10-02T11:00:00Z'), event(2, 'finished', '2026-10-02T11:01:00Z')];

function fixture(action, args) {
  const root = process.env.REMEDIATION_FIXTURE;
  const statePath = path.join(root, 'state.json');
  const state = JSON.parse(readFileSync(statePath));
  const save = () => writeFileSync(statePath, JSON.stringify(state));
  const emit = value => { save(); process.stdout.write(JSON.stringify(value)); };
  if (action === 'clock') { console.log(state.time); return; }
  if (action === 'sleep') { state.time += Number(args[0]) * 1000; save(); return; }
  assert.equal(action, 'gh');
  assert.equal(args[0], 'api');
  state.calls.push(args);
  if (state.scenario === 'api-error') { save(); process.stderr.write('mock API failure'); process.exit(19); }
  if (state.scenario === 'malformed-json') { save(); console.log('not json'); return; }
  const endpointArgument = args.find(arg => /^\/?repos\//.test(arg));
  const endpoint = endpointArgument?.startsWith('/') ? endpointArgument : `/${endpointArgument}`;
  if (args.includes('POST') && endpoint.endsWith('/reviews')) {
    const input = JSON.parse(readFileSync(args[args.indexOf('--input') + 1]));
    assert.equal(input.event, 'REQUEST_CHANGES');
    assert.equal(input.commit_id, sha);
    state.review = { id: 50, state: 'CHANGES_REQUESTED', body: input.body, commit_id: sha, submitted_at: boundary };
    state.posts++;
    if (state.scenario === 'uncertain-review') {
      save(); process.stderr.write('mock connection lost after review mutation'); process.exit(19);
    }
    emit(state.review); return;
  }
  if (endpoint?.endsWith('/reviews/50')) {
    if (['phase-a-readback-overrun', 'bad-readback-overrun'].includes(state.scenario)) state.time += 120000;
    emit({ ...state.review, body: ['bad-readback', 'bad-readback-overrun'].includes(state.scenario) ? 'not published' : state.review.body }); return;
  }
  if (args.includes('POST') && endpoint.endsWith('/assignees')) {
    const input = JSON.parse(readFileSync(args[args.indexOf('--input') + 1]));
    assert.deepEqual(input, { assignees: ['copilot-swe-agent[bot]'], agent_assignment: { target_repo: 'owner/repo', base_branch: 'campaign-base' } });
    state.assigned++;
    if (state.scenario === 'uncertain-reassignment') {
      save(); process.stderr.write('mock connection lost after reassignment mutation'); process.exit(19);
    }
    emit({ assignees: [{ login: 'copilot-swe-agent[bot]' }] }); return;
  }
  const scenario = state.scenario;
  if (args[1] === 'graphql') {
    assert(args.includes('--paginate') && args.includes('--slurp'));
    const poll = state.poll++;
    if (scenario === 'phase-a-query-overrun' && poll === 1) state.time += 120000;
    if (scenario === 'phase-c-query-overrun' && poll === 2) state.time += 600000;
    if (scenario === 'final-query-overrun' && poll === 3) state.time += 600000;
    const changed = poll > 0 && ['changed', 'partial', 'stale', 'newer-start', 'failed-diff'].includes(scenario);
    const pr = {
      number: 11, state: 'OPEN', isDraft: true, baseRefName: 'campaign-base',
      headRefOid: changed ? newSha : sha,
      body: poll > 0 && ['evidence', 'pagination'].includes(scenario) ? 'Concrete evidence on HEAD ' + sha : 'Original body',
      closingIssuesReferences: {
        nodes: [{ number: 6, repository: { nameWithOwner: 'owner/repo' } }],
        pageInfo: { hasNextPage: false, endCursor: null },
      },
    };
    if (scenario === 'wrong-base' && poll > 0) pr.baseRefName = 'main';
    if (scenario === 'closed') pr.state = 'CLOSED';
    if (scenario === 'ready') pr.isDraft = false;
    if (scenario === 'head-before-request') pr.headRefOid = newSha;
    if (scenario === 'wrong-issue') pr.closingIssuesReferences.nodes[0].number = 60;
    if (scenario === 'wrong-repo') pr.closingIssuesReferences.nodes[0].repository.nameWithOwner = 'other/repo';
    if (scenario === 'head-drift' && poll >= 3) pr.headRefOid = newSha;
    if (scenario === 'graphql-error') { emit([{ errors: [{ message: 'unavailable' }] }]); return; }
    const page = data => ({ data: { repository: { pullRequest: data } } });
    emit(scenario === 'pagination' ? [
      page({ ...pr, closingIssuesReferences: { nodes: [], pageInfo: { hasNextPage: true, endCursor: 'next' } } }),
      page(pr),
    ] : [page(pr)]);
    return;
  }
  if (endpoint?.includes('/timeline?')) {
    assert(args.includes('--paginate') && args.includes('--slurp'));
    const poll = state.poll - 1;
    let events = [...old];
    if (scenario === 'active-before-request') events.push(event(3, 'started', '2026-10-02T11:59:59Z'));
    if (scenario === 'same-second-baseline') events = [event(90, 'started'), event(91, 'finished')];
    if (poll > 0) {
      let fresh = [event(100, 'started'), event(101, 'finished')];
      if (['partial', 'stale'].includes(scenario)) fresh = [event(100, 'started')];
      if (scenario === 'newer-start') fresh.push(event(102, 'started', '2026-10-02T12:00:01Z'));
      if (scenario === 'head-drift' && poll >= 3) fresh.push(event(102, 'started', '2026-10-02T12:00:01Z'));
      if (scenario === 'orphan-finish') fresh = [event(101, 'finished')];
      if (scenario === 'reverse-same-second') fresh = [event(99, 'finished'), event(100, 'started')];
      if (['failed', 'failed-diff'].includes(scenario)) fresh = [event(100, 'started'), event(101, 'finished_failure')];
      if (scenario === 'missing-timestamp') delete fresh[0].created_at;
      if (scenario === 'invalid-date') fresh[0].created_at = '2026-99-02T12:00:00Z';
      if (scenario === 'conflicting-id') fresh.push(event(101, 'started'));
      if (scenario === 'missing-app') delete fresh[0].performed_via_github_app;
      if (scenario === 'foreign-agent') fresh = fresh.map(e => ({ ...e, performed_via_github_app: { slug: 'copilot-pull-request-reviewer' } }));
      if (['no-engagement', 'uncertain-reassignment'].includes(scenario) || (scenario === 'reassign' && state.assigned === 0)) fresh = [];
      if (scenario === 'stale-only') fresh = [];
      if (scenario === 'late-completion' && poll >= 2) state.time += 600000;
      if (scenario === 'phase-a-timeline-overrun' && poll === 1) state.time += 120000;
      if (scenario === 'final-timeline-overrun' && poll === 3) state.time += 600000;
      events.push(...fresh);
    }
    emit(scenario === 'pagination' ? [
      [...events.slice(0, 2), ...Array.from({ length: 98 }, () => ({ event: 'commented' }))],
      events.slice(2),
    ] : [events]);
    return;
  }
  if (endpoint === '/repos/owner/repo/issues/11') {
    emit({ body: scenario === 'evidence' ? 'Concrete evidence on HEAD ' + sha : 'Original body' }); return;
  }
  throw new Error(`Unexpected mock gh call: ${args.join(' ')}`);
}

if (process.argv[2] === '--fixture') {
  fixture(process.argv[3], process.argv.slice(4));
} else {
  const pwshAvailable = spawnSync('pwsh', ['-NoProfile', '-Command', 'exit 0']).status === 0;
  const platforms = ['bash', ...(pwshAvailable ? ['pwsh'] : [])];
  const parity = new Map();
  function environment(root, scenario) {
    writeFileSync(path.join(root, 'state.json'), JSON.stringify({
      scenario, time: 1000000, poll: 0, posts: 0, assigned: 0, calls: [],
    }));
    for (const action of ['gh', 'clock', 'sleep']) {
      writeFileSync(path.join(root, action),
        `#!/bin/sh\nexec ${quote(process.execPath)} ${quote(self)} --fixture ${action} "$@"\n`, { mode: 0o755 });
    }
    writeFileSync(path.join(root, 'review.txt'), '@copilot Please publish concrete evidence.\n');
    return {
      ...process.env, REMEDIATION_FIXTURE: root, GH_COMMAND: path.join(root, 'gh'),
      SHEPHERD_REMEDIATION_CLOCK_COMMAND: path.join(root, 'clock'),
      SHEPHERD_REMEDIATION_SLEEP_COMMAND: path.join(root, 'sleep'),
      GH_TOKEN: '', GITHUB_TOKEN: '',
    };
  }
  function invoke(shell, root, env, scripts = path.join(plugin, 'scripts')) {
    const review = path.join(root, 'review.txt');
    const args = shell === 'bash'
      ? [path.join(scripts, 'request-cca-remediation.sh'), 'owner/repo', '6', '11', 'campaign-base', sha, review]
      : ['-NoProfile', '-File', path.join(scripts, 'request-cca-remediation.ps1'),
        '-Repo', 'owner/repo', '-Issue', '6', '-PullRequest', '11',
        '-BaseBranch', 'campaign-base', '-ExpectedHead', sha, '-ReviewBodyPath', review];
    const result = spawnSync(shell, args, { env, encoding: 'utf8', timeout: 90000 });
    assert.equal(result.error, undefined, String(result.error));
    let json;
    try { json = JSON.parse(result.stdout); }
    catch { assert.fail(`No result JSON (${shell}): ${result.stdout}\n${result.stderr}`); }
    return { ...result, json };
  }
  const cases = [
    ['evidence', 0, 'cycle-completed'],
    ['no-publication', 0, 'cycle-completed'],
    ['changed', 0, 'cycle-completed'],
    ['same-second-baseline', 0, 'cycle-completed'],
    ['pagination', 0, 'cycle-completed'],
    ['partial', 8, 'changed-head-incomplete-cycle'],
    ['stale', 8, 'changed-head-incomplete-cycle'],
    ['newer-start', 8, 'changed-head-incomplete-cycle'],
    ['head-drift', 8, 'changed-head-incomplete-cycle'],
    ['orphan-finish', 8, 'unchanged-head-timeout'],
    ['reverse-same-second', 8, 'unchanged-head-timeout'],
    ['foreign-agent', 8, 'unchanged-head-timeout'],
    ['stale-only', 8, 'unchanged-head-timeout'],
    ['no-engagement', 8, 'unchanged-head-timeout'],
    ['reassign', 0, 'cycle-completed'],
    ['late-completion', 8, 'unchanged-head-timeout'],
    ['failed', 9, 'agent-failed'],
    ['failed-diff', 9, 'agent-failed'],
    ['active-before-request', 4, 'invalid-state'],
    ['missing-timestamp', 4, 'invalid-state'],
    ['invalid-date', 4, 'invalid-state'],
    ['conflicting-id', 4, 'invalid-state'],
    ['missing-app', 4, 'invalid-state'],
    ['wrong-base', 4, 'invalid-state'],
    ['closed', 4, 'invalid-state'],
    ['ready', 4, 'invalid-state'],
    ['wrong-issue', 4, 'invalid-state'],
    ['wrong-repo', 4, 'invalid-state'],
    ['head-before-request', 4, 'invalid-state'],
    ['graphql-error', 4, 'invalid-state'],
    ['bad-readback', 4, 'invalid-state'],
    ['api-error', 3, 'api-error'],
    ['uncertain-review', 3, 'api-error'],
    ['uncertain-reassignment', 3, 'api-error'],
    ['malformed-json', 4, 'invalid-state'],
  ];
  for (const shell of platforms) {
    test(`${shell}: native runtime remediation matrix`, async t => {
      const root = mkdtempSync(path.join(tmpdir(), 'cca-remediation-contract-'));
      try {
        for (const [scenario, code, outcome] of cases) {
          await t.test(scenario, () => {
            const env = environment(root, scenario);
            const result = invoke(shell, root, env);
            assert.equal(result.status, code, result.stderr);
            assert.equal(result.json.outcome, outcome, result.stderr);
            assert.equal(result.json.schemaVersion, 1);
            assert.equal(result.json.acceptance, 'not-evaluated');
            assert.equal(result.json.nextAction, code === 0 ? 'revalidate' : 'stop');
            const { observedAt, message, ...stable } = result.json;
            if (shell === 'bash') parity.set(scenario, stable);
            else if (parity.has(scenario)) assert.deepEqual(stable, parity.get(scenario));
            assert(!result.stdout.includes('SHEPHERD COMPLETE'));
            if (code !== 0) assert(result.stderr.includes('SHEPHERD FAILED'));
            const state = JSON.parse(readFileSync(path.join(root, 'state.json')));
            assert(state.posts <= 1);
            assert(state.assigned <= 1);
            if (scenario === 'reassign') assert.equal(state.assigned, 1);
            if (scenario === 'evidence') assert.equal(result.json.descriptionChanged, true);
            if (scenario === 'no-publication') assert.equal(result.json.descriptionChanged, false);
            if (scenario === 'changed') assert.equal(result.json.headChanged, true);
            if (scenario === 'active-before-request') assert.equal(state.posts, 0);
            if (scenario.startsWith('uncertain-')) {
              assert.equal(state.posts, 1);
              assert.equal(state.assigned, scenario === 'uncertain-reassignment' ? 1 : 0);
              assert(result.stderr.includes('request state may need reconciliation'));
            }
            if (code === 8) assert(result.json.elapsedMs >= 600000);
          });
        }
      } finally { rmSync(root, { recursive: true, force: true }); }
    });

    test(`${shell}: source, standalone and published skill invocation`, () => {
      const root = mkdtempSync(path.join(tmpdir(), 'cca-layout-contract-'));
      try {
        const env = environment(root, 'evidence');
        const published = path.join(root, 'published');
        const standalone = path.join(root, 'standalone');
        cpSync(path.join(plugin, 'scripts'), path.join(published, 'scripts'), { recursive: true });
        cpSync(skill, path.join(published, 'skills', skillName), { recursive: true });
        cpSync(skill, standalone, { recursive: true });
        for (const scripts of [
          path.join(skill, 'scripts'), path.join(published, 'scripts'), path.join(standalone, 'scripts'),
        ]) {
          environment(root, 'evidence');
          assert.equal(invoke(shell, root, env, scripts).status, 0);
        }
      } finally { rmSync(root, { recursive: true, force: true }); }
    });

    test(`${shell}: claimed-but-unpublished evidence fails existing publication gate`, () => {
      const root = mkdtempSync(path.join(tmpdir(), 'cca-publication-contract-'));
      try {
        const expected = path.join(root, 'expected.md');
        writeFileSync(expected, 'Concrete evidence on HEAD ' + sha);
        for (const scenario of ['evidence', 'no-publication']) {
          const env = environment(root, scenario);
          const lifecycle = invoke(shell, root, env);
          assert.equal(lifecycle.status, 0);
          const file = path.join(plugin, 'scripts', `verify-github-issue-body.${shell === 'bash' ? 'sh' : 'ps1'}`);
          const args = shell === 'bash' ? [file, 'owner/repo', '11', expected, '1', '0']
            : ['-NoProfile', '-File', file, '-Repository', 'owner/repo', '-IssueNumber', '11',
              '-ExpectedBodyPath', expected, '-MaxAttempts', '1', '-DelaySeconds', '0',
              '-GitHubCli', env.GH_COMMAND];
          const result = spawnSync(shell, args, { env, encoding: 'utf8', timeout: 20000 });
          assert.equal(result.status === 0, scenario === 'evidence', result.stdout + result.stderr);
        }
      } finally { rmSync(root, { recursive: true, force: true }); }
    });
  }
  test('skill invokes maintained helper in both remediation paths, never accepts completion alone', () => {
    const instructions = readFileSync(path.join(skill, 'SKILL.md'), 'utf8');
    const reference = readFileSync(path.join(skill, 'references/cca-remediation-loop.md'), 'utf8');
    assert(instructions.includes('Use the same committed remediation helper as Step 7'));
    assert(reference.includes('cycle-completed'));
    assert(reference.includes('ineffective\nremediation'));
    assert(reference.includes('rerun all normal gates'));
    assert(!reference.includes('while ['));
    for (const asset of ['request-cca-remediation.sh', 'request-cca-remediation.ps1', 'cca-remediation-state.jq']) {
      assert(instructions.includes(`scripts/${asset}`));
      assert(existsSync(path.join(skill, 'scripts', asset)));
    }
  });
  test('Bash production clock uses date seconds and executes without Perl', () => {
    const root = mkdtempSync(path.join(tmpdir(), 'cca-wall-clock-contract-'));
    try {
      const dateCommand = spawnSync('sh', ['-c', 'command -v date'], { encoding: 'utf8' });
      assert.equal(dateCommand.status, 0);
      const env = environment(root, 'evidence');
      env.SHEPHERD_REMEDIATION_CLOCK_COMMAND = '';
      env.PATH = `${root}${path.delimiter}${process.env.PATH}`;
      const dateCalls = path.join(root, 'date-calls');
      const perlCalled = path.join(root, 'perl-called');
      writeFileSync(path.join(root, 'date'), `#!/bin/sh\nprintf '%s\\n' "$*" >> ${quote(dateCalls)}\nexec ${quote(dateCommand.stdout.trim())} "$@"\n`, { mode: 0o755 });
      writeFileSync(path.join(root, 'perl'), `#!/bin/sh\nprintf 'unexpected Perl invocation\\n' > ${quote(perlCalled)}\nexit 99\n`, { mode: 0o755 });
      const before = Date.now();
      const result = invoke('bash', root, env);
      const after = Date.now();
      assert.equal(result.status, 0, result.stderr);
      assert.equal(result.json.outcome, 'cycle-completed');
      assert.equal(result.json.elapsedMs % 1000, 0);
      assert(result.json.elapsedMs >= 0 && result.json.elapsedMs <= after - before + 1000);
      assert(readFileSync(dateCalls, 'utf8').split('\n').filter(line => line === '+%s').length >= 3);
      assert(!existsSync(perlCalled));
    } finally { rmSync(root, { recursive: true, force: true }); }
  });
  test('Bash soft deadlines reject overdue polls and retain one-time Phase A re-engagement', async t => {
    const root = mkdtempSync(path.join(tmpdir(), 'cca-soft-deadline-contract-'));
    try {
      for (const [scenario, status, assigned] of [
        ['phase-a-query-overrun', 0, 1],
        ['phase-a-timeline-overrun', 0, 1],
        ['phase-a-readback-overrun', 0, 1],
        ['bad-readback-overrun', 4, 0],
        ['phase-c-query-overrun', 8, 0],
        ['late-completion', 8, 0],
        ['final-query-overrun', 8, 0],
        ['final-timeline-overrun', 8, 0],
      ]) {
        await t.test(scenario, () => {
          const result = invoke('bash', root, environment(root, scenario));
          assert.equal(result.status, status, result.stderr);
          const state = JSON.parse(readFileSync(path.join(root, 'state.json')));
          assert.equal(state.posts, 1);
          assert.equal(state.assigned, assigned);
          assert.equal(result.json.acceptance, 'not-evaluated');
          assert.equal(result.json.nextAction, status === 0 ? 'revalidate' : 'stop');
          if (status === 0) {
            assert.equal(result.json.outcome, 'cycle-completed');
            assert(result.json.elapsedMs >= 120000);
            assert(state.poll >= 3, 'Completion must use new Phase C observations, not the expired Phase A response');
          }
          if (status === 8) {
            assert.equal(result.json.outcome, 'unchanged-head-timeout');
            assert(result.json.elapsedMs >= 600000);
          }
        });
      }
    } finally { rmSync(root, { recursive: true, force: true }); }
  });
  test('isolated installer ships executable skill assets without touching the active installation', () => {
    const root = mkdtempSync(path.join(tmpdir(), 'cca-install-contract-'));
    try {
      const env = { ...environment(root, 'evidence'), COPILOT_HOME: path.join(root, 'copilot-home') };
      const installed = spawnSync('bash', [path.join(plugin, 'scripts/install-task-shepherd.sh')],
        { env, encoding: 'utf8', timeout: 60000 });
      assert.equal(installed.status, 0, installed.stdout + installed.stderr);
      const globalSkill = path.join(env.COPILOT_HOME, 'skills', skillName);
      const installedPlugin = path.join(env.COPILOT_HOME, 'plugins/shepherd-task');
      for (const asset of ['request-cca-remediation.sh', 'request-cca-remediation.ps1', 'cca-remediation-state.jq']) {
        for (const destination of [globalSkill, path.join(installedPlugin, 'skills', skillName)]) {
          assert.deepEqual(readFileSync(path.join(destination, 'scripts', asset)), readFileSync(path.join(skill, 'scripts', asset)));
        }
        for (const destination of [globalSkill, path.join(installedPlugin, 'skills', skillName)]) {
          assert(!existsSync(path.join(destination, 'scripts/cca-remediation-clock.pl')));
        }
      }
      for (const shell of platforms) {
        environment(root, 'evidence');
        assert.equal(invoke(shell, root, env, path.join(installedPlugin, 'scripts')).status, 0);
        environment(root, 'evidence');
        assert.equal(invoke(shell, root, env, path.join(globalSkill, 'scripts')).status, 0);
      }
    } finally { rmSync(root, { recursive: true, force: true }); }
  });
  test('outer Stage 30 outcome assertion does not accept a lifecycle result or ineffective correction', () => {
    const root = mkdtempSync(path.join(tmpdir(), 'cca-outcome-contract-'));
    try {
      for (const final of [
        '{"outcome":"cycle-completed","acceptance":"not-evaluated","nextAction":"revalidate"}',
        '**SHEPHERD FAILED:** Ineffective remediation on PR #11 for task #6: requested implementation is unchanged.',
      ]) {
        const transcript = path.join(root, 'session.md');
        writeFileSync(transcript, `# Copilot CLI Session\n\n### Copilot\n\n${final}\n`);
        const result = spawnSync('bash', [
          path.join(plugin, 'scripts/assert-shepherd-session-outcome.sh'), transcript, '30', '6', '11',
        ], { encoding: 'utf8' });
        assert.notEqual(result.status, 0, result.stdout + result.stderr);
      }
    } finally { rmSync(root, { recursive: true, force: true }); }
  });
  if (!pwshAvailable) test('PowerShell runtime matrix', { skip: 'PowerShell 7 is not installed' }, () => {});
}
