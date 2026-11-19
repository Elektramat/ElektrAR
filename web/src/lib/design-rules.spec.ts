import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

/**
 * Enforces the checkable rules of ../../../DESIGN.md on the web app, like
 * KabelmeterTests/DesignRulesTests.swift does for the iPhone app: no system colours, no
 * see-through fills, no grey materials. Colours are tokens in the `:root` blocks of app.css;
 * white (text on blue or green, the cart circle) is the only literal colour allowed elsewhere.
 */
const forbidden: { rule: string; pattern: RegExp }[] = [
	{
		rule: 'System colour (use a token from app.css)',
		pattern:
			/\b(color|background|background-color|fill|stroke|border(-[a-z]+)*|outline)\s*[:=]\s*["']?[^;"']*\b(purple|pink|yellow|teal|cyan|orange|green|red|mint|indigo|brown|magenta|violet|lime|aqua|fuchsia|gold)\b/
	},
	{
		rule: 'Literal colour (use a token from app.css)',
		pattern: /#(?!fff\b|ffffff\b)[0-9a-f]{3,8}\b/i
	},
	{
		rule: 'See-through colour (only black shadows and backdrops)',
		pattern: /\b(rgba?|hsla?)\((?!\s*0,\s*0,\s*0\b)/
	},
	{ rule: 'See-through colour mix', pattern: /\bcolor-mix\(/ },
	{ rule: 'Grey material (use a white card)', pattern: /\bbackdrop-filter\b/ }
];

function violations(line: string): string[] {
	return forbidden.filter(({ pattern }) => pattern.test(line)).map(({ rule }) => rule);
}

const src = join(fileURLToPath(new URL('.', import.meta.url)), '..');

function files(dir: string): string[] {
	return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
		const path = join(dir, entry.name);
		if (entry.isDirectory()) return files(path);
		return /\.(svelte|css)$/.test(entry.name) ? [path] : [];
	});
}

describe('DESIGN.md rules', () => {
	it('every screen uses tokens only', () => {
		const found: string[] = [];
		const all = files(src);
		expect(all.length).toBeGreaterThan(0);
		for (const file of all) {
			let inRoot = false;
			readFileSync(file, 'utf8')
				.split('\n')
				.forEach((line, index) => {
					const trimmed = line.trim();
					// The token definitions themselves.
					if (/^:root\s*\{/.test(trimmed)) inRoot = true;
					if (inRoot) {
						if (trimmed === '}') inRoot = false;
						return;
					}
					// The browser bar colour cannot be a CSS variable.
					if (trimmed.startsWith('/*') || trimmed.startsWith('*') || /theme-color/.test(line))
						return;
					for (const rule of violations(line)) {
						found.push(`${file.slice(src.length + 1)}:${index + 1}: ${rule}: ${trimmed}`);
					}
				});
		}
		expect(found, `DESIGN.md rules broken:\n${found.join('\n')}`).toEqual([]);
	});

	it('catches known bad lines and lets good ones through', () => {
		const bad = [
			'color: purple;',
			'background: rgba(255, 255, 255, 0.18);',
			'background: #34c759;',
			'backdrop-filter: blur(20px);',
			'<span style="color: orange">',
			'background: color-mix(in srgb, var(--color-primary) 30%, transparent);'
		];
		for (const line of bad) expect(violations(line), line).not.toEqual([]);

		const good = [
			'background: var(--color-primary);',
			'color: #fff;',
			'box-shadow: 0 2px 8px rgba(0, 0, 0, 0.18);',
			'border-top: 1px solid var(--color-black-15);',
			'{#each segments as s, index (s.id)}'
		];
		for (const line of good) expect(violations(line), line).toEqual([]);
	});
});
