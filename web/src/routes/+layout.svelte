<script lang="ts">
	import '../app.css';
	import type { LayoutProps } from './$types';

	let { children }: LayoutProps = $props();
</script>

<svelte:head>
	<title>Elektramat Kabelmeter</title>
	<meta
		name="description"
		content="Bereken hoeveel kabel je nodig hebt en wat het kost, en zet het in je winkelmand."
	/>
	<link rel="icon" href="/favicon.png" />
	<link rel="apple-touch-icon" href="/apple-touch-icon.png" />
	<link rel="manifest" href="/manifest.webmanifest" />
	<meta name="theme-color" content="#196cae" />
	<meta name="apple-mobile-web-app-capable" content="yes" />
	<meta name="apple-mobile-web-app-title" content="Kabelmeter" />
</svelte:head>

{@render children()}
