#!/usr/bin/env node

import { createInterface } from 'node:readline';
import { getStatus, runCaptured } from './submodule-governance.mjs';

const tools = [
  {
    name: 'get_submodule_status',
    description: 'Read submodule governance state without modifying the repository.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'check_submodules',
    description: 'Run the read-only governance check used by pre-push.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'accept_current_pointers',
    description: 'Create one main-repository commit accepting all current submodule pointers when allowed by policy. This modifies Git history and requires confirm=true.',
    inputSchema: {
      type: 'object',
      properties: { confirm: { type: 'boolean', description: 'Must be true after user approval.' } },
      required: ['confirm'],
    },
  },
  {
    name: 'sync_recorded_pointers',
    description: 'Checkout submodules to commits recorded by the main repository. This modifies submodule worktrees and requires confirm=true.',
    inputSchema: {
      type: 'object',
      properties: { confirm: { type: 'boolean', description: 'Must be true after user approval.' } },
      required: ['confirm'],
    },
  },
];

function respond(id, result) {
  process.stdout.write(`${JSON.stringify({ jsonrpc: '2.0', id, result })}\n`);
}

function textResult(value, isError = false) {
  return { content: [{ type: 'text', text: typeof value === 'string' ? value : JSON.stringify(value, null, 2) }], isError };
}

function callTool(name, args = {}) {
  if (name === 'get_submodule_status') return textResult(getStatus());
  if (name === 'check_submodules') {
    const result = runCaptured('check');
    return textResult(result.stdout + result.stderr, !result.ok);
  }
  if (name === 'accept_current_pointers') {
    if (args.confirm !== true) return textResult('This operation creates a commit. Re-run with confirm=true after user approval.', true);
    const result = runCaptured('accept-pointers');
    return textResult(result.stdout + result.stderr, !result.ok);
  }
  if (name === 'sync_recorded_pointers') {
    if (args.confirm !== true) return textResult('This operation modifies submodule worktrees. Re-run with confirm=true after user approval.', true);
    const result = runCaptured('sync');
    return textResult(result.stdout + result.stderr, !result.ok);
  }
  return textResult(`Unknown tool: ${name}`, true);
}

const lines = createInterface({ input: process.stdin, crlfDelay: Infinity });
lines.on('line', (line) => {
  if (!line.trim()) return;
  let request;
  try {
    request = JSON.parse(line);
    if (request.method === 'initialize') {
      respond(request.id, {
        protocolVersion: request.params?.protocolVersion || '2025-06-18',
        capabilities: { tools: {} },
        serverInfo: { name: 'submodule-governance', version: '0.1.0' },
      });
    } else if (request.method === 'tools/list') {
      respond(request.id, { tools });
    } else if (request.method === 'tools/call') {
      respond(request.id, callTool(request.params?.name, request.params?.arguments));
    } else if (request.id !== undefined) {
      respond(request.id, {});
    }
  } catch (error) {
    if (request?.id !== undefined) respond(request.id, textResult(String(error), true));
  }
});
