#!/usr/bin/env node
'use strict';

var fs = require('fs');
var sessions = JSON.parse(fs.readFileSync(0, 'utf8'));
function sanitize(value) {
    return String(value == null ? '' : value).replace(/[\p{Cc}\p{Zl}\p{Zp}]/gu, ' ');
}
function textElements(text) {
    if (typeof Intl.Segmenter === 'function') {
        return Array.from(new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(text),
            function (part) { return part.segment; });
    }
    // Node 12 has Unicode properties but not Intl.Segmenter. Retain combining
    // marks, emoji modifiers, flags, and joined emoji as whole display elements.
    var result = [];
    Array.from(text).forEach(function (character) {
        var previous = result.length ? result[result.length - 1] : '';
        var extend = /[\p{Grapheme_Extend}\p{Mc}\p{Emoji_Modifier}\u200d]/u.test(character);
        var joined = previous.endsWith('\u200d') && /\p{Extended_Pictographic}/u.test(previous) &&
            /\p{Extended_Pictographic}/u.test(character);
        var flag = /^\p{Regional_Indicator}$/u.test(previous) && /^\p{Regional_Indicator}$/u.test(character);
        if (previous && (extend || joined || flag)) result[result.length - 1] += character;
        else result.push(character);
    });
    return result;
}
var displays = sessions.map(function (session) {
    var name = sanitize(session.name);
    var elements = textElements(name);
    return {
        name: name,
        label: elements.length > 80 ? elements.slice(0, 77).join('') + '...' : name,
        branch: sanitize(session.branch)
    };
});
var counts = Object.create(null);
displays.forEach(function (display) { counts[display.label] = (counts[display.label] || 0) + 1; });
process.stdout.write(JSON.stringify(sessions.map(function (session, index) {
    var display = displays[index];
    return {
        label: display.label + (counts[display.label] > 1 && display.branch.trim() ? ' (' + display.branch + ')' : ''),
        help: 'Id: ' + sanitize(session.id) + '\nName: ' + display.name +
            '\nRepository: ' + sanitize(session.repository) + '\nBranch: ' + display.branch +
            '\nCwd: ' + sanitize(session.cwd) + '\nUpdated: ' + sanitize(session.updatedAt || '(unknown)') +
            '\nEvents: ' + sanitize(session.eventCount)
    };
})));
