<script>
	import { onMount } from 'svelte';
	import { csvParse } from 'd3-dsv';
	import { base } from '$app/paths';

	import '$lib/assets/global-styles.css';
	import Logo from '$lib/LogoTop.svelte';
	import Footer from '$lib/Footer.svelte';
	import AuthorDate from '$lib/AuthorDate.svelte';
	import TitleStandard from '$lib/TitleStandard.svelte';


	let isLoading = true;
	let loadError = '';
	let mounted = false;


	let b1Data = [];

	const years = [2016, 2018, 2020, 2022, 2024];
	let yearA = 2016;
	let yearB = 2024;
	$: selectedYears = [yearA, yearB].sort((a, b) => a - b);

	let locViewMode = 'raw'; // 'raw' | 'percent'

	const categoryOrder = [
		'Sales to Canadian federal government',
		'Sales to non-government entities in Canadian defence, marine & aerospace sectors',
		'Sales to other Canadian customers',
		'Domestic breakdown not specified',
		'Sales to U.S. federal government',
		'Sales to non-government entities in U.S. defence, marine & aerospace sectors',
		'Sales to other U.S. customers',
		'U.S. export breakdown not specified',
		'Sales to Central America, Caribbean, Mexico and South America',
		'Sales to United Kingdom',
		'Sales to Europe other than United Kingdom',
		'Sales to Middle East and Africa',
		'Sales to Australia',
		'Sales to New Zealand',
		'Sales to Asia and Oceania - Other than Australia & New Zealand',
		'Other countries breakdown not specified',
		'Breakdown not specified for any category',
	];

	const regionColors = {
		canada: 'var(--brandLightBlue)',
		us: 'var(--brandMedBlue)',
		world: 'rgba(255,255,255,0.5)',
		unknown: 'rgba(255,255,255,0.2)',
	};

	const regionGroups = [
		{ id: 'canada', label: 'Canada' },
		{ id: 'us', label: 'United States' },
		{ id: 'world', label: 'Rest of World' },
	];
	let selectedRegions = new Set(['canada', 'us', 'world']);

	function toggleRegion(id) {
		if (selectedRegions.has(id) && selectedRegions.size > 1) {
			selectedRegions.delete(id);
		} else {
			selectedRegions.add(id);
		}
		selectedRegions = selectedRegions;
	}

	function normalizeLabel(value) {
		return String(value ?? '').replace(/\s+/g, ' ').trim();
	}

	function normalizeCategory(cat) {
		const c = cat.trim();
		if (c.includes('non-government') && c.includes('Canadian'))
			return 'Sales to non-government entities in Canadian defence, marine & aerospace sectors';
		if (c.includes('non-government') && (c.includes('U.S.') || c.includes('US')))
			return 'Sales to non-government entities in U.S. defence, marine & aerospace sectors';
		if (c.startsWith('Sales to Central America'))
			return 'Sales to Central America, Caribbean, Mexico and South America';
		if (c === 'Sales to Asia and Oceania')
			return 'Sales to Asia and Oceania - Other than Australia & New Zealand';
		return c;
	}

	function resolveRegion(category) {
		const text = normalizeLabel(category).toLowerCase();
		if (text.includes('united states') || text.includes('u.s.')) return 'us';
		if (text.includes('canadian') || text.startsWith('domestic')) return 'canada';
		if (text.includes('breakdown not specified for any category')) return 'unknown';
		return 'world';
	}

	function parseNum(str) {
		if (!str) return 0;
		return Number(String(str).replace(/,/g, '').trim()) || 0;
	}

	// RENAMED to avoid collision with your existing formatValue(value) used by the cartograms
	function formatSalesValue(val, total, currentMode) {
		if (currentMode === 'percent') {
			if (!total) return '0.0%';
			return ((val / total) * 100).toFixed(1) + '%';
		}
		if (val >= 1e9) return `$${(val / 1e9).toFixed(2)}B`;
		if (val >= 1e6) return `$${(val / 1e6).toFixed(1)}M`;
		return `$${val.toLocaleString()}`;
	}

	$: allCategories = (() => {
		const cats = [...new Set(b1Data.map(d => d.category))];
		return cats.sort((a, b) => {
			const ai = categoryOrder.indexOf(a);
			const bi = categoryOrder.indexOf(b);
			if (ai === -1 && bi === -1) return a.localeCompare(b);
			if (ai === -1) return 1;
			if (bi === -1) return -1;
			return ai - bi;
		});
	})();

	$: locAllYears = selectedYears.map(y => {
		const items = b1Data.filter(d => d.year === y);
		const total = items.reduce((sum, d) => sum + d.amount, 0);
		return { year: y, items, total };
	});

	$: if (yearB === yearA) {
		yearB = years.find(y => y !== yearA) ?? years[0];
	}

	async function loadData() {
		console.time('loadData: total');
		try {
			const locRes = await fetch(`${base}/data/B1B2B3.csv`).then((r) => r.text());


			b1Data = csvParse(locRes).map((row) => ({
				category: normalizeCategory(row['Type of Sale'].trim()),
				amount: parseNum(row['Amount']),
				year: Number(row['Year'])
			})).filter((d) => d.year && d.amount > 0);

		} finally {
			isLoading = false;
			console.timeEnd('loadData: total');
		}
	}
	
	onMount(() => {
		mounted = true;
		loadData();
	});

	
</script>

<Logo logoType="White" backgroundColor="var(--brandGray90)" />

<main class="page">
	<TitleStandard title="Defence sales and exports from the Department of National Defence" />
	<div class="text">
		<AuthorDate
			authors="<a href='https://schoolofcities.utoronto.ca/people/karen-chapple/' target='_blank'>Karen Chapple</a>, <a href='https://discover.research.utoronto.ca/8035-tara-vinodrai' target='_blank'>Tara Vinodrai</a>, <a href='https://www.linkedin.com/in/yihoi-jung-0b95351b5/' target='_blank'>Yihoi Jung</a>, <a href='https://www.linkedin.com/in/sarahbridgetgibbons/'>Sarah Gibbons</a>, Andrew Feng"
			date="Last updated August 4th, 2026."
		/>
		<p>
			This table describes the destinations of goods and services sold by Canadian firms (from the CDACCMS dataset).

		</p>
	</div>

	{#if isLoading}
		<div class="status">Loading contract data…</div>
	{:else if loadError}
		<div class="status error">{loadError}</div>
	{:else}


		<div class="text">
			<div class="filter-group inline-filters">
				<span class="filter-label">Compare years</span>
				<div class="year-pair">
					<select class="year-select" bind:value={yearA}>
						{#each years as y}<option value={y}>{y}</option>{/each}
					</select>
					<span class="year-vs">vs</span>
					<select class="year-select" bind:value={yearB}>
						{#each years.filter(y => y !== yearA) as y}<option value={y}>{y}</option>{/each}
					</select>
				</div>
			</div>
		</div>

        <!-- TABULAR LIST: LOCATIONS -->
        <div class="text">
            <h3>Sales by location</h3>
            <p>Sales breakdown across all survey years, ordered by most recent year value.</p>
            <div class="filter-group inline-filters">
                <span class="filter-label">Sales metric</span>
                <div class="button-group">
                    <button class="filter-toggle-button {locViewMode === 'raw' ? 'selected' : ''}" on:click={() => (locViewMode = 'raw')}>
                        Show Raw
                    </button>
                    <button class="filter-toggle-button {locViewMode === 'percent' ? 'selected' : ''}" on:click={() => (locViewMode = 'percent')}>
                        Show Percent
                    </button>
                </div>
            </div>
            <div class="filter-group inline-filters">
                <span class="filter-label">Region</span>
                <div class="button-group">
                    {#each regionGroups as r}
                        <button
                            class="filter-toggle-button {selectedRegions.has(r.id) ? 'selected' : ''}"
                            on:click={() => toggleRegion(r.id)}>
                            {r.label}
                        </button>
                    {/each}
                </div>
            </div>
            <div class="table-wrap">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th class="align-left">Location Breakdown</th>
                            {#each selectedYears as y}
                                <th>{y}</th>
                            {/each}
                        </tr>
                    </thead>
                    <tbody>
                        {#each allCategories.filter(cat => {
                            const r = resolveRegion(cat);
                            return selectedRegions.has(r) || (selectedRegions.has('world') && r === 'unknown');
                        }) as cat}
                            {@const region = resolveRegion(cat)}
                            <tr>
                                <td class="align-left cell-category">
                                    <span class="region-bar" style="background:{regionColors[region]}"></span>{cat}
                                </td>
                                {#each locAllYears as { items, total }}
                                    {@const val = items.find(d => d.category === cat)?.amount ?? 0}
                                    <td>{val > 0 ? formatSalesValue(val, total, locViewMode) : '—'}</td>
                                {/each}
                            </tr>
                        {/each}
                        <tr class="total-row">
                            <td class="align-left cell-category">Total</td>
                            {#each locAllYears as { total, items }}
                                {@const filteredTotal = items
                                    .filter(d => {
                                        const r = resolveRegion(d.category);
                                        return selectedRegions.has(r) || (selectedRegions.has('world') && r === 'unknown');
                                    })
                                    .reduce((sum, d) => sum + d.amount, 0)}
                                <td>{formatSalesValue(filteredTotal, filteredTotal, locViewMode)}</td>
                            {/each}
                        </tr>
                    </tbody>
                </table>
            </div>
        </div>
	{/if}

	
</main>

<Footer />

<style>
	.region-bar { display:inline-block; width:3px; height:1em; border-radius:2px; margin-right:8px; vertical-align:middle; flex-shrink:0; }
	.cell-category { display:flex; align-items:center; min-width:300px; font-family:OpenSans; }
	.year-pair { display:flex; align-items:center; gap:10px; }
	.year-vs { font-family:OpenSansBold; font-size:13px; color:var(--brandGray); }
	.filter-group.inline-filters { margin-top:12px; }
	.button-group { display:flex; gap:8px; }
	.filter-toggle-button { padding:6px 12px; border:1px solid var(--brandGray); border-radius:3px; cursor:pointer; background-color:var(--brandWhite); color:var(--brandGray90); font-family:OpenSans; font-size:13px; }
	.filter-toggle-button.selected { background-color:var(--brandMedBlue); color:white; border-color:var(--brandDarkBlue); }
	.table-wrap { width:100%; margin:0 auto; overflow-x:auto; border:1px solid var(--brandGray); border-radius:3px; background:var(--brandGray90); }
	.data-table { width:100%; margin:0 auto; border-collapse:collapse; font-family:OpenSans; font-size:14px; }
	.data-table th, .data-table td { color:var(--brandWhite); padding:6px 8px; border-bottom:1px solid var(--brandGray); text-align:right; }
	.data-table th:first-child, .data-table td:first-child { border-right:1px solid var(--brandGray); }
	.data-table th { background:var(--brandGray90); font-family:OpenSansBold; }
	.align-left { text-align:left !important; }
	.data-table tbody tr:last-child td { border-bottom:none; }
	.total-row { font-family:OpenSansBold; }
	.page {
		max-width: 1200px;
		margin: 0 auto;
		padding: 20px 24px 80px;
		display: flex;
		flex-direction: column;
		gap: 24px;
	}
	.slider-row {
		display: flex;
		align-items: center;
		gap: 8px;
	}
	.year-slider {
		width: 140px;
		accent-color: var(--brandWhite);
	}
	.year-slider-value {
		font-family: OpenSansBold;
		font-size: 13px;
		color: var(--brandWhite);
		min-width: 34px;
	}
	.status {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		padding: 60px 20px;
		min-height: 200px;
		gap: 12px;
		font-family: OpenSans;
		color: var(--brandGray90);
	}
	.status.error {
		color: var(--brandRed);
		border: 1px solid var(--brandRed);
		border-radius: 6px;
		padding: 20px;
	}
	.filter-group {
		display: flex;
		flex-direction: column;
	}
	.filter-row {
		display: flex;
		flex-wrap: wrap;
		gap: 24px;
		align-items: flex-start;
	}
	.filter-label {
		font-family: OpenSansBold;
		font-size: 13px;
		margin-bottom: 3px;
		color: var(--brandWhite);
	}
	.toggle-btn {
		padding: 4px 10px;
		border: 1px solid var(--brandWhite);
		border-radius: 3px;
		background: var(--brandGray90);
		color: var(--brandWhite);
		font-family: OpenSans;
		font-size: 13px;
		cursor: pointer;
	}
	.toggle-btn:hover { background: rgba(255,255,255,0.1); }
	.year-select {
		max-width: 280px;
		padding: 4px 6px;
		border: 1px solid var(--brandWhite);
		border-radius: 3px;
		background: var(--brandGray90);
		color: var(--brandWhite);
		font-family: OpenSans;
		font-size: 13px;
	}
	.year-select option {
		background: var(--brandGray90);
		color: var(--brandWhite);
	}
	.map-block {
		width: 100%;
	}
	@media (max-width: 720px) {
		.page {
			padding: 32px 16px 64px;
		}
	}
</style>
