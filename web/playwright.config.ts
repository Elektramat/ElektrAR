import { defineConfig } from '@playwright/test';

export default defineConfig({
	webServer: { command: 'pnpm run build && pnpm run preview', port: 4173 },
	testMatch: '**/*.e2e.{ts,js}',
	// Same phone size as the prototype checks.
	use: { viewport: { width: 390, height: 844 }, locale: 'nl-NL' }
});
