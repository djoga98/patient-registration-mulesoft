#!/usr/bin/env node
// Reads the JSON-lines application logs (see src/main/resources/log4j2.xml).
//
//   node scripts/log-events.js check <log-file> [from-line]
//       Every line from from-line (1-based, default 1) must be a JSON object. Every
//       application line (logger com.acme.patient.*) must carry a correlation ID, and
//       its message must be a JSON event whose correlationId equals the line's.
//       Prints a summary; exit code 1 when a check fails.
//
//   node scripts/log-events.js count <log-file> <correlation-id> <event> [field=value ...]
//       Prints how many application events with that correlation ID and event name
//       match all field=value pairs (values compared as strings).
'use strict';
const fs = require('fs');

const [command, file, ...rest] = process.argv.slice(2);
if (!['check', 'count'].includes(command) || !file) {
    console.error('usage: log-events.js check <log-file> [from-line] | count <log-file> <correlation-id> <event> [field=value ...]');
    process.exit(2);
}

const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
if (lines[lines.length - 1] === '') lines.pop();

const isAppLine = (line) => typeof line.logger === 'string' && line.logger.startsWith('com.acme.patient');
const parseEvent = (message) => {
    try {
        const event = JSON.parse(message);
        return event && typeof event === 'object' && typeof event.event === 'string' ? event : null;
    } catch (e) {
        return null;
    }
};

if (command === 'check') {
    const from = Math.max(1, parseInt(rest[0] || '1', 10));
    let total = 0, invalid = 0, app = 0, noCorrelation = 0, unstructured = 0, mismatched = 0;
    lines.slice(from - 1).forEach((text, i) => {
        total++;
        let line;
        try {
            line = JSON.parse(text);
        } catch (e) {
            invalid++;
            if (invalid <= 3) console.error(`line ${from + i}: not JSON: ${text.slice(0, 120)}`);
            return;
        }
        if (!isAppLine(line)) return;
        app++;
        if (!line.correlationId) noCorrelation++;
        const event = parseEvent(line.message);
        if (!event) unstructured++;
        else if (event.correlationId !== line.correlationId) mismatched++;
    });
    console.log(`${total} lines (${invalid} not JSON), ${app} application events: ` +
        `${noCorrelation} without correlation ID, ${unstructured} not a JSON event, ` +
        `${mismatched} with a different correlation ID in the message`);
    process.exit(total > 0 && app > 0 && invalid + noCorrelation + unstructured + mismatched === 0 ? 0 : 1);
}

const [correlationId, eventName, ...filters] = rest;
const wanted = filters.map((f) => f.split(/=(.*)/s).slice(0, 2));
let matches = 0;
for (const text of lines) {
    let line;
    try { line = JSON.parse(text); } catch (e) { continue; }
    if (!isAppLine(line) || line.correlationId !== correlationId) continue;
    const event = parseEvent(line.message);
    if (event && event.event === eventName && wanted.every(([k, v]) => String(event[k]) === v)) matches++;
}
console.log(matches);
