#!/usr/bin/env node
'use strict';

// Only public Azure origin shapes with exactly three unambiguous segments.
var fs = require('fs');
var url = fs.readFileSync(0, 'utf8');
var match;
if (!/[\s\\]/u.test(url)) {
    match = /^https:\/\/dev\.azure\.com\/([^/]+)\/(?:DefaultCollection\/)?([^/]+)\/_git\/([^/]+)\/?$/i.exec(url) ||
        /^https:\/\/([a-z0-9](?:[a-z0-9-]*[a-z0-9])?)\.visualstudio\.com\/(?:DefaultCollection\/)?([^/]+)\/_git\/([^/]+)\/?$/i.exec(url) ||
        /^(?:git@ssh\.dev\.azure\.com:|ssh:\/\/git@ssh\.dev\.azure\.com\/)v3\/([^/]+)\/([^/]+)\/([^/]+)\/?$/i.exec(url);
}
if (!match) process.exit(1);
var segments;
try {
    segments = match.slice(1).map(function (segment) {
        if (/%(?![0-9a-f]{2})/i.test(segment)) throw new Error('invalid escape');
        var decoded = decodeURIComponent(segment);
        if (!decoded || decoded !== decoded.trim() || decoded === '.' || decoded === '..' ||
            /[/\\?#\p{Cc}\p{Cf}\p{Zl}\p{Zp}\uFFFD]/u.test(decoded)) {
            throw new Error('ambiguous segment');
        }
        return decoded;
    });
} catch (_) {
    process.exit(1);
}
if (!/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/i.test(segments[0])) process.exit(1);
segments[0] = segments[0].toLowerCase();
segments[2] = segments[2].replace(/\.git$/i, '');
if (!segments[2].trim() || segments[2] === '.' || segments[2] === '..') process.exit(1);
process.stdout.write(segments.join('/') + '\n');
