// Uses the platform's installed SDK and mounts its scripts at test time.
// No proprietary generator is copied into this repository or into the image.
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const [platformDir, image] = process.argv.slice(2);
assert(platformDir && image, 'Usage: node tests/opensandbox.mjs PLATFORM_DIRECTORY IMAGE');
const require = createRequire(path.join(path.resolve(platformDir), 'package.json'));
const { Sandbox } = await import(pathToFileURL(require.resolve('@alibaba-group/opensandbox')).href);
const scriptDir = path.join(platformDir, 'src/lib/plugins/native/opensandbox/skill/scripts');
const started = performance.now();
let sandbox;

async function command(text) {
  const result = await sandbox.commands.run(text, { timeoutSeconds: 60 });
  const stderr = result.logs.stderr.map(log => log.text).join('');
  assert.equal(result.exitCode, 0, stderr);
  return result.logs.stdout.map(log => log.text).join('');
}

try {
  sandbox = await Sandbox.create({
    image,
    connectionConfig: {
      domain: process.env.OPENSANDBOX_TEST_DOMAIN ?? 'localhost:8090',
      protocol: 'http',
      useServerProxy: true,
      disableMetrics: true,
    },
    timeoutSeconds: 180,
    metadata: { purpose: 'CLO-1332-image-test' },
    volumes: [{
      name: 'workspace',
      mountPath: '/tmp',
      pvc: { claimName: `clo1332-test-${Date.now()}`, createIfNotExists: true, deleteOnSandboxTermination: true },
    }],
  });
  const startupMs = Math.round(performance.now() - started);
  assert.equal((await command('id -u')).trim(), '10001', 'OpenSandbox must preserve the image user');
  await command('mkdir -p /opt/skill/scripts /opt/skills/image-test/scripts /tmp/downloads');
  const names = (await readdir(scriptDir)).filter(name => name.endsWith('.py'));
  await sandbox.files.writeFiles(await Promise.all(names.map(async name => ({
    path: `/opt/skill/scripts/${name}`,
    data: await readFile(path.join(scriptDir, name)),
  }))));
  await sandbox.files.writeFiles([
    { path: '/opt/skills/image-test/scripts/binary.dat', data: Buffer.from([0, 255, 17, 42]) },
    { path: '/tmp/doc-spec.json', data: Buffer.from(JSON.stringify({ title: 'Offline integration', blocks: [{ type: 'paragraph', text: 'Mounted skill works' }] })) },
    { path: '/tmp/pptx-spec.json', data: Buffer.from(JSON.stringify({ title: 'Mounted deck', slides: [{ title: 'Evidence', bullets: ['Mounted skill works'] }] })) },
    { path: '/tmp/xlsx-spec.json', data: Buffer.from(JSON.stringify({ sheets: [{ name: 'Evidence', columns: ['Amount'], rows: [[42]] }] })) },
    { path: '/tmp/chart-spec.json', data: Buffer.from(JSON.stringify({ kind: 'bar', x: ['Evidence'], series: [{ name: 'Amount', values: [42] }] })) },
  ]);
  for (const [script, spec, output] of [
    ['make_docx', 'doc', 'document.docx'],
    ['make_pdf', 'doc', 'document.pdf'],
    ['make_pptx', 'pptx', 'deck.pptx'],
    ['make_xlsx', 'xlsx', 'sheet.xlsx'],
    ['make_chart', 'chart', 'chart.png'],
  ]) {
    await command(`python3 /opt/skill/scripts/${script}.py /tmp/${spec}-spec.json /tmp/${output}`);
  }
  const diagram = names.includes('make_diagram.py');
  if (diagram) {
    await command('python3 /opt/skill/scripts/make_diagram.py --selftest');
  }
  const checks = `
from pathlib import Path
from docx import Document
from pptx import Presentation
from openpyxl import load_workbook
from PIL import Image
assert 'Mounted skill works' in '\\n'.join(p.text for p in Document('/tmp/document.docx').paragraphs)
assert len(Presentation('/tmp/deck.pptx').slides) == 2
assert load_workbook('/tmp/sheet.xlsx').active['A2'].value == 42
assert Path('/tmp/document.pdf').read_bytes().startswith(b'%PDF-')
assert Image.open('/tmp/chart.png').width > 100
assert Path('/opt/skills/image-test/scripts/binary.dat').read_bytes() == bytes([0,255,17,42])
print('Mounted generators and binary resource: OK')
`;
  await sandbox.files.writeFiles([{ path: '/tmp/check.py', data: Buffer.from(checks) }]);
  console.log(await command('python3 /tmp/check.py'));
  console.log(JSON.stringify({ image, startupMs, mountedGenerators: names.length, diagramSelftest: diagram }));
} finally {
  if (sandbox) {
    try { await sandbox.kill(); } finally { await sandbox.close(); }
  }
}
