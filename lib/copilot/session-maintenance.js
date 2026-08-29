#!/usr/bin/env node
// session-maintenance.js — Copilot session maintenance algorithms ported from
// SessionMaintenance.ps1 (Repair-CopilotSessionEvents, Compress-CopilotSession,
// Merge-CopilotSession). Invoked by the copilot-session-maintenance bash wrapper.
//
// Node is used here (rather than bash+jq) because these operations require
// stateful reordering and synthesis of a JSONL event stream, which Node handles
// reliably. Node is always available where the Copilot CLI runs.
//
// Usage:
//   session-maintenance.js repair-events <sessionDir> [--no-backup]
//   session-maintenance.js compress <sessionDir> [--keep N] [--no-backup]
//   session-maintenance.js merge <newDir> <srcDir1> <srcDir2> [srcDirN...]
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const childProcess = require('child_process');

const workspaceYamlHelper = path.join(__dirname, 'workspace-yaml.sh');

// uuidv4 — random UUID compatible with older Node (no crypto.randomUUID).
function uuidv4() {
    const b = crypto.randomBytes(16);
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    const h = b.toString('hex');
    return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}

// copyRecursive — recursive copy compatible with older Node (no fs.cpSync).
function copyRecursive(src, dest) {
    const stat = fs.statSync(src);
    if (stat.isDirectory()) {
        fs.mkdirSync(dest, { recursive: true });
        for (const entry of fs.readdirSync(src)) {
            copyRecursive(path.join(src, entry), path.join(dest, entry));
        }
    } else {
        fs.mkdirSync(path.dirname(dest), { recursive: true });
        fs.copyFileSync(src, dest);
    }
}

function readLines(file) {
    if (!fs.existsSync(file)) return [];
    const text = fs.readFileSync(file, 'utf8');
    if (text.length === 0) return [];
    return text.replace(/\r?\n$/, '').split(/\r?\n/);
}

function writeLines(file, lines) {
    fs.writeFileSync(file, lines.join('\r\n') + '\r\n', 'utf8');
}

function parseEventLines(lines) {
    const parsed = [];
    let droppedMalformed = 0;
    for (let i = 0; i < lines.length; i++) {
        const raw = lines[i];
        if (raw.trim() === '') continue;
        try {
            const json = JSON.parse(raw);
            if (!json || typeof json !== 'object' || Array.isArray(json) || typeof json.type !== 'string') {
                droppedMalformed++;
                continue;
            }
            const toolRequests = (json.type === 'assistant.message' && json.data &&
                Array.isArray(json.data.toolRequests))
                ? json.data.toolRequests.map(t => t && t.toolCallId).filter(Boolean)
                : [];
            parsed.push({
                idx: i,
                type: json.type,
                toolCallId: json.data && json.data.toolCallId,
                toolRequests,
                raw,
                json,
            });
        } catch (err) {
            droppedMalformed++;
        }
    }
    return { parsed, droppedMalformed };
}

// repairEvents — port of Repair-CopilotSessionEvents. Takes raw JSONL lines and
// returns sanitized lines plus the malformed-line count.
function repairEvents(lines) {
    if (!lines || lines.length === 0) return { lines: lines || [], droppedMalformed: 0 };

    const parseResult = parseEventLines(lines);
    const parsed = parseResult.parsed;

    const requestMap = {}; // toolCallId -> assistant.message index
    for (let i = 0; i < parsed.length; i++) {
        if (parsed[i].type === 'assistant.message') {
            for (const tid of parsed[i].toolRequests) requestMap[tid] = i;
        }
    }

    const completeMap = {}; // toolCallId -> [indices]
    const startMap = {};
    for (let i = 0; i < parsed.length; i++) {
        const ev = parsed[i];
        if (ev.type === 'tool.execution_complete' && ev.toolCallId) {
            if (!completeMap[ev.toolCallId]) completeMap[ev.toolCallId] = [];
            completeMap[ev.toolCallId].push(i);
        }
        if (ev.type === 'tool.execution_start' && ev.toolCallId) {
            if (!startMap[ev.toolCallId]) startMap[ev.toolCallId] = [];
            startMap[ev.toolCallId].push(i);
        }
    }

    // Orphaned tool events: complete/start appearing before their request.
    const relocate = new Set();
    for (const tid of Object.keys(requestMap)) {
        const reqIdx = requestMap[tid];
        for (const ci of (completeMap[tid] || [])) if (ci < reqIdx) relocate.add(ci);
        for (const si of (startMap[tid] || [])) if (si < reqIdx) relocate.add(si);
    }

    const output = [];
    for (let i = 0; i < parsed.length; i++) {
        const ev = parsed[i];
        if (relocate.has(i)) continue;
        if (ev.type === 'session.error' || ev.type === 'session.warning') continue;
        if (ev.json.id === '' ||
            (ev.type === 'tool.execution_complete' && ev.json.data && ev.json.data.model === 'unknown')) {
            continue;
        }
        output.push(ev.raw);
        if (ev.type === 'assistant.message' && ev.toolRequests.length > 0) {
            for (const tid of ev.toolRequests) {
                for (const si of (startMap[tid] || [])) if (relocate.has(si)) output.push(parsed[si].raw);
                for (const ci of (completeMap[tid] || [])) if (relocate.has(ci)) output.push(parsed[ci].raw);
            }
        }
    }

    // Synthesize missing completions.
    const outputParsed = output.map((raw, i) => ({ idx: i, json: JSON.parse(raw) }));
    const finalRequestMap = {};
    const finalCompleteSet = new Set();
    for (let i = 0; i < outputParsed.length; i++) {
        const j = outputParsed[i].json;
        if (j.type === 'assistant.message' && j.data && j.data.toolRequests) {
            for (const req of j.data.toolRequests) finalRequestMap[req.toolCallId] = i;
        }
        if (j.type === 'tool.execution_complete' && j.data && j.data.toolCallId) {
            finalCompleteSet.add(j.data.toolCallId);
        }
    }

    const missing = Object.keys(finalRequestMap).filter(tid => !finalCompleteSet.has(tid));
    if (missing.length > 0) {
        const insertions = [];
        for (const tid of missing) {
            const assistIdx = finalRequestMap[tid];
            const assistJson = outputParsed[assistIdx].json;
            const interactionId = assistJson.data && assistJson.data.interactionId;
            const model = (assistJson.data && assistJson.data.model && assistJson.data.model !== 'unknown')
                ? assistJson.data.model : 'claude-sonnet-4';
            for (let j = assistIdx + 1; j < output.length; j++) {
                const ej = JSON.parse(output[j]);
                if (ej.type === 'assistant.turn_end') {
                    const synth = {
                        type: 'tool.execution_complete',
                        id: uuidv4(),
                        timestamp: ej.timestamp,
                        data: {
                            toolCallId: tid,
                            model,
                            interactionId,
                            success: true,
                            result: { content: '[Session repair: tool execution data unavailable]' },
                        },
                    };
                    insertions.push({ insertBefore: j, json: JSON.stringify(synth) });
                    break;
                }
            }
        }
        insertions.sort((a, b) => b.insertBefore - a.insertBefore);
        for (const ins of insertions) output.splice(ins.insertBefore, 0, ins.json);
    }

    return { lines: output, droppedMalformed: parseResult.droppedMalformed };
}

function assertValidSession(lines, description) {
    if (!lines || lines.length === 0) {
        throw new Error(description + ' contains no valid events.');
    }
    let hasSessionStart = false;
    for (const line of lines) {
        const event = JSON.parse(line);
        if (event.type === 'session.start') hasSessionStart = true;
    }
    if (!hasSessionStart) {
        throw new Error(description + ' contains no valid session.start event.');
    }
}

function reportMalformed(count) {
    if (count > 0) {
        process.stderr.write(`Dropped ${count} malformed JSONL line${count === 1 ? '' : 's'}.\n`);
    }
}

function backup(file, noBackup) {
    if (!noBackup && fs.existsSync(file)) fs.copyFileSync(file, file + '.bak');
}

function cmdRepairEvents(dir, noBackup) {
    const events = path.join(dir, 'events.jsonl');
    const lines = readLines(events);
    if (lines.length === 0) { process.stderr.write('No events to repair.\n'); return; }
    const result = repairEvents(lines);
    assertValidSession(result.lines, 'Session');
    backup(events, noBackup);
    writeLines(events, result.lines);
    reportMalformed(result.droppedMalformed);
    process.stderr.write(`Wrote ${result.lines.length} events (was ${lines.length}).\n`);
}

function cmdCompress(dir, keep, noBackup) {
    const events = path.join(dir, 'events.jsonl');
    const lines = readLines(events);
    if (lines.length === 0) { process.stderr.write('No events.jsonl found.\n'); return; }

    const inputResult = repairEvents(lines);
    assertValidSession(inputResult.lines, 'Session');
    const repairedLines = inputResult.lines;
    const userIndices = [];
    let sessionStartIndex = -1;
    const eventIds = new Array(repairedLines.length);
    for (let i = 0; i < repairedLines.length; i++) {
        const j = JSON.parse(repairedLines[i]);
        eventIds[i] = j.id;
        if (j.type === 'user.message') userIndices.push(i);
        else if (j.type === 'session.start') sessionStartIndex = i;
    }
    if (userIndices.length <= keep) {
        if (repairedLines.length !== lines.length ||
            repairedLines.some((line, index) => line !== lines[index])) {
            backup(events, noBackup);
            writeLines(events, repairedLines);
        }
        reportMalformed(inputResult.droppedMalformed);
        process.stderr.write(`Session has only ${userIndices.length} conversations, no compaction needed.\n`);
        return;
    }
    const cutIndex = userIndices[userIndices.length - keep];
    const output = [];
    const keptEventIds = new Set();
    if (sessionStartIndex >= 0) {
        output.push(repairedLines[sessionStartIndex]);
        if (eventIds[sessionStartIndex]) keptEventIds.add(eventIds[sessionStartIndex]);
    }
    for (let i = cutIndex; i < repairedLines.length; i++) {
        if (i === sessionStartIndex) continue;
        output.push(repairedLines[i]);
        if (eventIds[i]) keptEventIds.add(eventIds[i]);
    }

    // Clean up rewind-snapshots referencing deleted events.
    const snapIndex = path.join(dir, 'rewind-snapshots', 'index.json');
    let filteredSnapshotIndex = null;
    if (fs.existsSync(snapIndex)) {
        const index = JSON.parse(fs.readFileSync(snapIndex, 'utf8'));
        if (index.snapshots) {
            const filtered = index.snapshots.filter(s => !s.eventId || keptEventIds.has(s.eventId));
            filteredSnapshotIndex = JSON.stringify({ version: 1, snapshots: filtered }, null, 2);
        }
    }

    const outputResult = repairEvents(output);
    assertValidSession(outputResult.lines, 'Compacted session');
    backup(events, noBackup);
    if (filteredSnapshotIndex !== null) backup(snapIndex, noBackup);
    writeLines(events, outputResult.lines);
    if (filteredSnapshotIndex !== null) {
        fs.writeFileSync(snapIndex, filteredSnapshotIndex, 'utf8');
    }
    reportMalformed(inputResult.droppedMalformed + outputResult.droppedMalformed);
    process.stderr.write(`Compacted: ${lines.length} -> ${outputResult.lines.length} events ` +
        `(kept last ${keep} conversations).\n`);
}

function firstEventTimestamp(lines) {
    const first = lines[0];
    if (!first) return null;
    try { return new Date(JSON.parse(first).timestamp).getTime(); } catch { return null; }
}

function runWorkspaceYaml(args, expectedFailure) {
    const result = childProcess.spawnSync('bash', [workspaceYamlHelper].concat(args), { encoding: 'utf8' });
    if (result.error) throw result.error;
    if (result.status !== 0 && !expectedFailure) {
        throw new Error((result.stderr || 'workspace.yaml helper failed').trim());
    }
    return result;
}

function workspaceGet(file, key) {
    return runWorkspaceYaml(['get', file, key], false).stdout;
}

function workspaceHas(file, key) {
    return runWorkspaceYaml(['has', file, key], true).status === 0;
}

function workspaceSetStrings(file, values) {
    const args = ['set-string', file];
    for (const key of Object.keys(values)) args.push(key, values[key]);
    runWorkspaceYaml(args, false);
}

function workspaceSetRaw(file, values) {
    const args = ['set-raw', file];
    for (const key of Object.keys(values)) args.push(key, values[key]);
    runWorkspaceYaml(args, false);
}

function cmdMerge(newDir, srcDirs) {
    if (srcDirs.length < 2) { process.stderr.write('At least two sessions are required to merge.\n'); process.exit(1); }

    const sessions = srcDirs.map(d => {
        const wsFile = path.join(d, 'workspace.yaml');
        const ws = fs.readFileSync(wsFile, 'utf8');
        const eventResult = repairEvents(readLines(path.join(d, 'events.jsonl')));
        assertValidSession(eventResult.lines, 'Source session ' + path.basename(d));
        return {
            dir: d,
            ws,
            wsFile,
            updated: workspaceGet(wsFile, 'updated_at'),
            cwd: workspaceGet(wsFile, 'cwd'),
            repairedEvents: eventResult.lines,
            droppedMalformed: eventResult.droppedMalformed,
        };
    });

    // Validate a single working directory (case-insensitive).
    const cwds = [...new Set(sessions.map(s => (s.cwd || '').toLowerCase()))];
    if (cwds.length > 1) {
        process.stderr.write('Cannot merge sessions from different directories.\n');
        process.exit(1);
    }

    // Order sessions by earliest event timestamp.
    const ordered = [...sessions].sort((a, b) =>
        (firstEventTimestamp(a.repairedEvents) || 0) - (firstEventTimestamp(b.repairedEvents) || 0));

    const newId = path.basename(newDir);
    const skipLifecycle = new Set(['session.shutdown', 'session.resume', 'session.error', 'session.warning',
        'session.compaction_start', 'session.compaction_complete', 'session.truncation',
        'session.context_changed', 'abort']);
    let isFirst = true;
    const outLines = [];
    for (const s of ordered) {
        for (const line of s.repairedEvents) {
            const evt = JSON.parse(line);
            if (evt.type === 'session.start') {
                if (isFirst) {
                    evt.data.sessionId = newId;
                    evt.id = uuidv4();
                    outLines.push(JSON.stringify(evt));
                    isFirst = false;
                }
                continue;
            }
            if (skipLifecycle.has(evt.type)) continue;
            outLines.push(line);
        }
    }
    const mergedEventResult = repairEvents(outLines);
    assertValidSession(mergedEventResult.lines, 'Merged session');

    const snapshotIndexes = [];
    for (const s of sessions) {
        const idxFile = path.join(s.dir, 'rewind-snapshots', 'index.json');
        snapshotIndexes.push(fs.existsSync(idxFile)
            ? JSON.parse(fs.readFileSync(idxFile, 'utf8'))
            : null);
    }

    for (const sub of ['checkpoints', 'files', 'research', 'rewind-snapshots',
        path.join('rewind-snapshots', 'backups')]) {
        fs.mkdirSync(path.join(newDir, sub), { recursive: true });
    }
    const newEvents = path.join(newDir, 'events.jsonl');
    writeLines(newEvents, mergedEventResult.lines);

    // Merge checkpoints/index.md.
    const byUpdated = [...sessions].sort((a, b) => (a.updated || '').localeCompare(b.updated || ''));
    const checkpointRows = [];
    for (const s of byUpdated) {
        const cp = path.join(s.dir, 'checkpoints', 'index.md');
        if (fs.existsSync(cp)) {
            for (const line of readLines(cp)) if (/^\|\s*\d+/.test(line)) checkpointRows.push(line);
        }
    }
    let n = 1;
    const renumbered = checkpointRows.map(r => r.replace(/^\|\s*\d+/, `| ${n++}`));
    const header = ['# Checkpoint History',
        'Checkpoints are listed in chronological order. Checkpoint 1 is the oldest, higher numbers are more recent.',
        '', '| # | Title | File |', '|---|-------|------|'];
    fs.writeFileSync(path.join(newDir, 'checkpoints', 'index.md'), header.concat(renumbered).join('\n') + '\n', 'utf8');

    // Merge rewind-snapshots.
    const snapshots = [];
    for (let sessionIndex = 0; sessionIndex < sessions.length; sessionIndex++) {
        const s = sessions[sessionIndex];
        const idx = snapshotIndexes[sessionIndex];
        if (idx && idx.snapshots) snapshots.push(...idx.snapshots);
        const backupsDir = path.join(s.dir, 'rewind-snapshots', 'backups');
        if (fs.existsSync(backupsDir)) {
            for (const f of fs.readdirSync(backupsDir)) {
                fs.copyFileSync(path.join(backupsDir, f), path.join(newDir, 'rewind-snapshots', 'backups', f));
            }
        }
    }
    snapshots.sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime());
    fs.writeFileSync(path.join(newDir, 'rewind-snapshots', 'index.json'),
        JSON.stringify({ version: 1, snapshots }, null, 2), 'utf8');

    // Copy files and research.
    for (const s of sessions) {
        for (const sub of ['files', 'research']) {
            const src = path.join(s.dir, sub);
            if (fs.existsSync(src)) {
                for (const f of fs.readdirSync(src)) {
                    copyRecursive(path.join(src, f), path.join(newDir, sub, f));
                }
            }
        }
    }

    // Workspace metadata from the most recently updated session.
    const primary = [...sessions].sort((a, b) => (b.updated || '').localeCompare(a.updated || ''))[0];
    const now = new Date().toISOString();
    const names = byUpdated
        .map(s => workspaceGet(s.wsFile, 'name') || workspaceGet(s.wsFile, 'summary'))
        .filter(x => x && x !== '(no summary)');
    const mergedSummary = [...new Set(names)].join(' + ') || 'merged session';

    const newWorkspace = path.join(newDir, 'workspace.yaml');
    fs.writeFileSync(newWorkspace, primary.ws, 'utf8');
    const stringUpdates = {};
    if (workspaceHas(primary.wsFile, 'name')) stringUpdates.name = mergedSummary;
    if (workspaceHas(primary.wsFile, 'summary')) stringUpdates.summary = mergedSummary;
    if (!workspaceHas(primary.wsFile, 'name') && !workspaceHas(primary.wsFile, 'summary')) {
        stringUpdates.name = mergedSummary;
    }
    if (Object.keys(stringUpdates).length > 0) workspaceSetStrings(newWorkspace, stringUpdates);
    workspaceSetRaw(newWorkspace, { id: newId, updated_at: now });
    if (workspaceHas(primary.wsFile, 'summary_count')) {
        workspaceSetRaw(newWorkspace, { summary_count: '0' });
    }
    fs.writeFileSync(path.join(newDir, 'vscode.metadata.json'), '{}', 'utf8');

    // Merge plan.md.
    const plans = [];
    for (const s of byUpdated) {
        const pf = path.join(s.dir, 'plan.md');
        if (fs.existsSync(pf)) {
            const c = fs.readFileSync(pf, 'utf8').trim();
            if (c) plans.push(c);
        }
    }
    if (plans.length > 0) {
        fs.writeFileSync(path.join(newDir, 'plan.md'), plans.join('\n\n---\n\n'), 'utf8');
    }

    reportMalformed(sessions.reduce((total, session) => total + session.droppedMalformed, 0) +
        mergedEventResult.droppedMalformed);
    process.stdout.write(newId + '\n');
}

function main() {
    const [, , cmd, ...rest] = process.argv;
    switch (cmd) {
        case 'repair-events': {
            const dir = rest[0];
            const noBackup = rest.includes('--no-backup');
            cmdRepairEvents(dir, noBackup);
            break;
        }
        case 'compress': {
            const dir = rest[0];
            const keepIdx = rest.indexOf('--keep');
            const keepText = keepIdx >= 0 ? rest[keepIdx + 1] : '5';
            if (!/^[1-9][0-9]*$/.test(keepText || '')) {
                process.stderr.write('--keep requires a positive integer.\n');
                process.exit(2);
            }
            const keep = Number(keepText);
            if (!Number.isSafeInteger(keep)) {
                process.stderr.write('--keep requires a positive integer.\n');
                process.exit(2);
            }
            const noBackup = rest.includes('--no-backup');
            cmdCompress(dir, keep, noBackup);
            break;
        }
        case 'merge': {
            const newDir = rest[0];
            const srcDirs = rest.slice(1);
            cmdMerge(newDir, srcDirs);
            break;
        }
        default:
            process.stderr.write('Unknown command: ' + cmd + '\n');
            process.exit(2);
    }
}

try {
    main();
} catch (err) {
    process.stderr.write((err && err.message ? err.message : String(err)) + '\n');
    process.exit(1);
}
