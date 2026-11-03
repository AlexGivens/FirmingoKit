#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createInterface } from 'node:readline';

/** Opt-in official-client compatibility check. Archived report data is not a new compiler/device pass. */
const usage = 'Usage: node Tools/Workbench/check-mcp-interop.mjs INSTALLED_CLIENT_PACKAGE_ROOT NEW_OUTPUT\n'
  + 'Requires local @modelcontextprotocol/client 2.4.0 and @modelcontextprotocol/sdk 1.32.2.\n'
  + 'Starts only a temporary private Unix broker fixture and MCP child processes; no TLS/app/device/compiler.';
if (process.argv.slice(2).join(' ') === '--help') { console.log(usage); process.exit(0); }
if (process.argv.length !== 4) throw new Error(usage);
const clientRoot = resolve(process.argv[2]), output = resolve(process.argv[3]);
const source = fileURLToPath(new URL('.', import.meta.url));
const root = resolve(source, '../..');
const pins = { '@modelcontextprotocol/client': '2.4.0', '@modelcontextprotocol/sdk': '1.32.2' };
for (const [name, version] of Object.entries(pins)) {
  const metadata = JSON.parse(readFileSync(join(clientRoot, 'node_modules', name, 'package.json')));
  if (metadata.name !== name || metadata.version !== version) throw new Error('Select the explicitly pinned official client packages');
}
if (!readFileSync(join(clientRoot, 'package-lock.json')).equals(readFileSync(join(source, 'MCPClient/package-lock.json'))))
  throw new Error('Use the reviewed optional-client lockfile');
mkdirSync(output, { mode: 0o700 });

/** Reuse the production broker/handler with exact archived bytes; this fixture never opens a mobile listener. */
const fixtureCode = String.raw`
import importlib.util,json,os,signal,sys
from pathlib import Path
source,report,base=map(Path,sys.argv[1:])
spec=importlib.util.spec_from_file_location('paired',source);paired=importlib.util.module_from_spec(spec);spec.loader.exec_module(paired)
broker=paired.Broker('https://127.0.0.1:1/','a'*64)
reply=json.loads(report.read_text());invite=broker.invite('Archived parser fixture; no live app')
session=broker.pair(invite['token'],{key:reply[key] for key in ('schema','instanceID','appIdentifier','appVersion','processID')})
sid=session['sessionID'];broker.command(sid,reply['command'])
body=dict(schema=1,sessionID=sid,instanceID=reply['instanceID'],ack=0,reply=None)
broker.exchange(session['token'],body,wait=0);broker.exchange(session['token'],dict(body,ack=1,reply=reply),wait=0)
server=paired.ControlServer(str(base/'control.sock'),paired.ControlHandler);server.broker=broker;(base/'control.sock').chmod(0o600)
print(json.dumps(dict(sessionID=sid,commandID=reply['command']['commandID'],scenarioID=reply['report']['scenarioID'],firmwareBuildID=reply['report']['firmwareBuildID'])),flush=True)
signal.signal(signal.SIGTERM,lambda *_:(_ for _ in ()).throw(KeyboardInterrupt()))
try:server.serve_forever()
except KeyboardInterrupt:pass
finally:server.server_close()
`;
const fixture = spawn('python3', ['-I', '-S', '-B', '-c', fixtureCode, join(source, 'paired.py'),
  join(root, 'docs/workbench-paired-reports/ipad/compiler-smoke.reply.json'), output], { stdio: ['ignore', 'pipe', 'pipe'] });
let fixtureErrors = '';
fixture.stderr.on('data', data => { fixtureErrors = (fixtureErrors + data.toString()).slice(0, 4096); });
const results = [];
try {
  const identity = await new Promise((accept, reject) => {
    const timer = setTimeout(() => reject(new Error('Local fixture startup exceeded ten seconds')), 10000);
    fixture.once('error', error => { clearTimeout(timer); reject(error); });
    fixture.once('exit', () => { clearTimeout(timer); reject(new Error('Fixture exited: ' + fixtureErrors)); });
    const lines = createInterface({ input: fixture.stdout });
    lines.once('line', line => {
      clearTimeout(timer);
      lines.close();
      try { accept(JSON.parse(line)); } catch (error) { reject(error); }
    });
  });
  for (const era of ['modern', 'legacy']) {
    const packagePath = join(clientRoot, 'node_modules', era === 'modern' ? '@modelcontextprotocol/client/dist' : '@modelcontextprotocol/sdk/dist/esm/client');
    const { Client } = await import(pathToFileURL(join(packagePath, era === 'modern' ? 'index.mjs' : 'index.js')));
    const { StdioClientTransport } = await import(pathToFileURL(join(packagePath, era === 'modern' ? 'stdio.mjs' : 'stdio.js')));
    const evidence = join(output, 'evidence-' + era); mkdirSync(evidence, { mode: 0o700 });
    const transport = new StdioClientTransport({ command: 'python3', args: ['-I', '-S', '-B', join(source, 'mcp-server.py'),
      '--directory', output, '--evidence-directory', evidence], stderr: 'pipe' });
    const client = new Client({ name: 'workbench-interop-fixture', version: '0.1.0' }, { capabilities: {} });
    let stderr = ''; transport.stderr?.on('data', chunk => { stderr = (stderr + chunk.toString()).slice(0, 4096); });
    try {
      await client.connect(transport);
      const tools = await client.listTools();
      if (tools.tools.length !== 4) throw new Error('Unexpected tool surface');
      const sessions = await client.callTool({ name: 'workbench_sessions', arguments: {} });
      if (sessions.isError) throw new Error('Session query failed');
      const report = await client.callTool({ name: 'workbench_result', arguments: {
        session_id: identity.sessionID, command_id: identity.commandID, scenario_id: identity.scenarioID,
        firmware_build_id: identity.firmwareBuildID } });
      if (report.isError || !report.structuredContent?.validatedReport || report.structuredContent?.scenarioCompletion !== 'passed')
        throw new Error('Archived report validation/export failed');
      results.push({ era, server: client.getServerVersion(), tools: tools.tools.map(item => item.name),
        validatedArchivedReport: true, evidence: report.structuredContent.evidence, stderr });
    } finally { await client.close(); }
  }
} finally {
  fixture.kill('SIGTERM');
  if (fixture.exitCode === null && fixture.signalCode === null) await new Promise((accept, reject) => {
    let hard;
    const timer = setTimeout(() => {
      fixture.kill('SIGKILL');
      hard = setTimeout(() => reject(new Error('Fixture exit was not observed')), 2000);
    }, 2000);
    fixture.once('exit', () => { clearTimeout(timer); clearTimeout(hard); accept(); });
  });
}
/** Record exact adapter/checker inputs and the installed lockfile without redistributing client dependencies. */
const sha = path => createHash('sha256').update(readFileSync(path)).digest('hex');
const record = { schema: 1, scope: 'Official-client stdio/local-broker interoperability over archived bytes; no live app, TLS, compiler or device execution',
  packages: pins, packageLockSHA256: sha(join(clientRoot, 'package-lock.json')), nodeVersion: process.version,
  sourceFiles: Object.fromEntries(['mcp-server.py', 'paired.py', 'workbench.py', 'check-mcp-interop.mjs'].map(name => [name, sha(join(source, name))])),
  fixtureStopped: true, results };
writeFileSync(join(output, 'results.json'), JSON.stringify(record, null, 2) + '\n', { flag: 'wx', mode: 0o600 });
console.log(JSON.stringify({ status: 'passed', eras: results.map(item => item.era), scope: record.scope, output }));
