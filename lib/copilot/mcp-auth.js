#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

// Config and scope values arrive on stdin so inline secrets never enter helper argv.
function validate(input) {
    const fields = input.split('\0');
    if (fields.pop() !== '' || fields.length % 2 !== 0) {
        throw new Error('Invalid MCP authentication validation input.');
    }
    const configs = [];
    const scopes = [];
    for (let i = 0; i < fields.length; i += 2) {
        if (fields[i] === 'config') configs.push(fields[i + 1]);
        else if (fields[i] === 'auth') scopes.push(fields[i + 1]);
        else throw new Error('Invalid MCP authentication validation input.');
    }
    if (!configs.length) {
        throw new Error('--mcp-github-auth requires --additional-mcp-config with the named remote server.');
    }
    const servers = new Map();
    configs.forEach(function (source) {
        let config;
        try {
            if (source.charAt(0) === '@') {
                let filename = source.slice(1);
                if (filename.indexOf('~/') === 0) {
                    filename = path.join(process.env.COPILOT_AUTH_HOME, filename.slice(2));
                }
                config = JSON.parse(fs.readFileSync(filename, 'utf8'));
            } else {
                config = JSON.parse(source);
            }
        } catch (_) {
            throw new Error('Cannot read or parse --additional-mcp-config. No authentication was enabled.');
        }
        if (!config || typeof config !== 'object' || !config.mcpServers ||
            typeof config.mcpServers !== 'object' || Array.isArray(config.mcpServers)) {
            throw new Error('--additional-mcp-config must contain an mcpServers map.');
        }
        Object.keys(config.mcpServers).forEach(function (name) {
            if (servers.has(name)) throw new Error('Duplicate explicit MCP server name.');
            servers.set(name, config.mcpServers[name]);
        });
    });
    const names = new Set();
    scopes.forEach(function (scope) {
        const match = /^([A-Za-z0-9][A-Za-z0-9._-]*)=(https?:\/\/([A-Za-z0-9.-]+|\[::1\])(?::[0-9]{1,5})?)\/?$/.exec(scope);
        if (!match || match[0] !== scope) {
            throw new Error('Invalid --mcp-github-auth scope: use server=https://host[:port], without credentials, path, query or fragment.');
        }
        const name = match[1];
        if (names.has(name)) throw new Error('Duplicate --mcp-github-auth server scope.');
        names.add(name);
        let origin;
        try {
            origin = new URL(match[2]);
        } catch (_) {
            throw new Error('Invalid --mcp-github-auth origin.');
        }
        if (origin.protocol === 'http:' && match[3] !== '127.0.0.1' && match[3] !== '[::1]') {
            throw new Error('--mcp-github-auth requires HTTPS or literal loopback HTTP.');
        }
        if (!servers.has(name)) {
            throw new Error('--mcp-github-auth server must be explicitly configured in --additional-mcp-config.');
        }
        const server = servers.get(name);
        let remote;
        try {
            if (!server || typeof server !== 'object' || Array.isArray(server) ||
                (server.type && server.type !== 'http' && server.type !== 'sse') ||
                typeof server.url !== 'string') throw new Error();
            remote = new URL(server.url);
        } catch (_) {
            throw new Error('--mcp-github-auth requires a configured remote HTTP/SSE server.');
        }
        if (remote.username || remote.password || remote.origin !== origin.origin) {
            throw new Error('Configured MCP URL must match the approved --mcp-github-auth origin without credentials.');
        }
    });
}

try {
    validate(fs.readFileSync(0, 'utf8'));
} catch (error) {
    console.error(error.message);
    process.exitCode = 1;
}
