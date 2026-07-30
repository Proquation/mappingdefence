<script>
	import { onMount } from 'svelte';
	import { csvParse } from 'd3-dsv';
	import { base } from '$app/paths';

	import '$lib/assets/global-styles.css';
	import Logo from '$lib/LogoTop.svelte';
	import Footer from '$lib/Footer.svelte';
	import AuthorDate from '$lib/AuthorDate.svelte';
	import TitleStandard from '$lib/TitleStandard.svelte';
	import ContractsCmaCartogram from './lib/ContractsCmaCartogram.svelte';
	import ContractsProvinceCartogram from './lib/ContractsProvinceCartogram.svelte';
	import ContractsWorldCartogram from './lib/ContractsWorldCartogram.svelte';

	let isLoading = true;
	let loadError = '';
	let mounted = false;

	// Geometry selection — contracts data has no CSD-level granularity
	const geometries = [
		{ id: 'cma', label: 'Census Metropolitan Area' },
		{ id: 'prov', label: 'Province' },
		{ id: 'world', label: 'World (by country)'}
	];
	let selectedGeometry = 'cma';

	// tier: "ALL" | "General Government Support" | "Industrial and Technical Support" | "Core Defence Industrial Complex"
	// let selectedTier = 'ALL';
	// // object_cluster: "ALL" | one of the 14 clusters
	// let selectedCluster = 'ALL';

	let yearOptions = [];
	let clusterOptions = [];
	let tierOptions = [];

	let metric = 'value'; // 'value' | 'count' | 'vendors'

	// Per-geometry data + geojson caches
	const aggData = {}; // { cma: [...rows], prov: [...] }
	const geojsonCache = {};

	let yearIndex = 0;
	let selectedYear = null; 

	const NO_FILTER = '__ANY__';

	let selectedTier = NO_FILTER;
	let selectedCluster = NO_FILTER;

	$: {
		if (aggData[selectedGeometry] && aggData[selectedGeometry].length > 0) {
			const data = aggData[selectedGeometry];
			const years = [...new Set(data.map(r => r.year))].sort();
			const tiers = [...new Set(data.map(r => r.tier))]
				.filter(t => Boolean(t) && t !== 'ALL')  // exclude the rollup pseudo-tier
				.sort();

			const clusters = [...new Set(data.map(r => r.object_cluster))]
				.filter(c => Boolean(c) && c !== 'ALL')
				.sort();

			yearOptions = years;
			tierOptions = tiers;
			clusterOptions = clusters;
			
			// Reset year if needed
			if (yearIndex >= years.length) {
				yearIndex = 0;
			}
			if (years.length > 0) {
				selectedYear = years[yearIndex];
			}
		}
	}

	$: {
		if (aggData.cma && aggData.cma.length > 0 && cmaGeojson) {
			const dataIds = new Set(aggData.cma.map(r => r.region_uid));
			const geoIds = new Set(cmaGeojson.features.map(f => f.id || f.properties?.CMA_UID || f.properties?.id));
			console.log('Sample data IDs:', Array.from(dataIds).slice(0, 5));
			console.log('Sample geo IDs:', Array.from(geoIds).slice(0, 5));
			console.log('Matching IDs:', [...dataIds].filter(id => geoIds.has(id)).length);
		}
	}

	let usGeojson = null;
	let darkMode = true;

	let militaryGeojson = null;
	let showMilitaryBases = false;

	async function ensureMilitaryGeojson() {
		if (militaryGeojson) return;
		militaryGeojson = await fetch(`${base}/geojson/military_bases_ca.geojson`).then((r) => r.json());
	}

	function toggleMilitaryBases() {
		showMilitaryBases = !showMilitaryBases;
		if (showMilitaryBases) ensureMilitaryGeojson();
	}

	function formatValue(value) {
		if (!Number.isFinite(value)) return 'N/A';
		if (Math.abs(value) >= 1_000_000_000) return `$${(value / 1_000_000_000).toFixed(2)}B`;
		if (Math.abs(value) >= 1_000_000) return `$${(value / 1_000_000).toFixed(2)}M`;
		if (Math.abs(value) >= 1_000) return `$${(value / 1_000).toFixed(1)}K`;
		return `$${value.toFixed(0)}`;
	}

	function normalizeRegionUid(id) {
		const s = String(id).trim();
		return /^\d+$/.test(s) ? s.padStart(3, '0') : s;
	}

	function parseAgg(csvText) {
		return csvParse(csvText).map((r) => ({
			region_uid: normalizeRegionUid(r.region_uid),
			region_name: r.region_name,
			year: Number(r.year),
			tier: r.tier,
			object_cluster: r.object_cluster,
			total_value: r.total_value === '' ? null : Number(r.total_value),
			n_contracts: r.n_contracts === '' ? null : Number(r.n_contracts),
			n_vendors: r.n_vendors === '' ? null : Number(r.n_vendors)
		}));
	}

	function roundToSigFigs(num, sig = 3) {
		if (!num) return 0;
		const magnitude = Math.pow(10, sig - Math.ceil(Math.log10(Math.abs(num))));
		return Math.round(num * magnitude) / magnitude;
	}

	
	$: filteredAllYears = (aggData[selectedGeometry] || []).filter(
		(r) =>
			(selectedTier === NO_FILTER || r.tier === selectedTier) &&
			(selectedCluster === NO_FILTER || r.object_cluster === selectedCluster)
	);


	$: {
		if (aggData.cma && aggData.cma.length > 0 && cmaGeojson) {
			const dataIds = new Set(aggData.cma.map(r => r.region_uid));
			const geoIds = new Set(cmaGeojson.features.map(f => normalizeRegionUid(f.properties.region_uid)));
			console.log('DATA region_uid sample:', Array.from(dataIds).slice(0, 10));
			console.log('GEO region_uid sample:', Array.from(geoIds).slice(0, 10));
			console.log('DATA count:', dataIds.size, 'GEO count:', geoIds.size);
			console.log('Matching:', [...dataIds].filter(id => geoIds.has(id)).length);
			console.log('In DATA but not GEO:', [...dataIds].filter(id => !geoIds.has(id)).slice(0, 10));
			console.log('In GEO but not DATA:', [...geoIds].filter(id => !dataIds.has(id)).slice(0, 10));
		}
	}

	// Same tier/cluster filter as activeRows, but across ALL years
	// $: filteredAllYears = (aggData[selectedGeometry] || []).filter(
	// 	(r) => r.tier === selectedTier && r.object_cluster === selectedCluster
	// );

	function computeSizeBins(rows, field) {
		const vals = rows
			.map((r) => r[field])
			.filter((v) => Number.isFinite(v) && v > 0)
			.sort((a, b) => a - b);

		if (!vals.length) return { thresholds: [1], radii: [3, 25] };

		const quantile = (p) => {
			const idx = (vals.length - 1) * p;
			const lo = Math.floor(idx), hi = Math.ceil(idx);
			if (lo === hi) return vals[lo];
			return vals[lo] + (vals[hi] - vals[lo]) * (idx - lo);
		};

		// 4 cut points -> up to 5 bins
		const raw = [0.50, 0.70, 0.90, 0.99].map(quantile);
		const thresholds = [...new Set(raw.map((v) => roundToSigFigs(v, 2)))].sort((a, b) => a - b);

		const allRadii = [4, 10, 17, 24, 32];
		const radii = allRadii.slice(0, thresholds.length + 1);

		return { thresholds, radii };
	}

	// direct reference to filteredAllYears so Svelte tracks the dependency correctly
	$: sizeBins =
		metric === 'count' ? computeSizeBins(filteredAllYears, 'n_contracts')
		: metric === 'vendors' ? computeSizeBins(filteredAllYears, 'n_vendors')
		: computeSizeBins(filteredAllYears, 'total_value');

	async function ensureGeojson(file) {
		if (geojsonCache[file]) return geojsonCache[file];
		console.time(`ensureGeojson: ${file}`);
		const gj = await fetch(`${base}/geojson/${file}.geojson`).then((r) => r.json());
		console.timeEnd(`ensureGeojson: ${file}`);
		console.log(`${file}: ${gj.features?.length ?? 0} features`);
		geojsonCache[file] = gj;
		return gj;
	}

	let cmaGeojson = null, provinceGeojson = null; let worldGeojson = null;

	$: if (mounted) {
		if (selectedGeometry === 'cma') {
			ensureGeojson('cma_boundaries').then((g) => (cmaGeojson = g));
			ensureGeojson('province-boundaries-simple').then((g) => (provinceGeojson = g));
			ensureGeojson('us_nation').then((g) => (usGeojson = g));
		}
		if (selectedGeometry === 'prov') {
			ensureGeojson('province-boundaries-simple').then((g) => (provinceGeojson = g));
			ensureGeojson('us_nation').then((g) => (usGeojson = g));
		}
		if (selectedGeometry === 'world') {
			ensureGeojson('world_countries').then((g) => (worldGeojson = g));   // new
		}
	}

	function aggregateByRegion(rows) {
		const byRegion = new Map();
		for (const r of rows) {
			const existing = byRegion.get(r.region_uid);
			if (existing) {
				existing.total_value += r.total_value || 0;
				existing.n_contracts += r.n_contracts || 0;
				existing.n_vendors += r.n_vendors || 0; // see vendor caveat below
			} else {
				byRegion.set(r.region_uid, {
					region_uid: r.region_uid,
					region_name: r.region_name,
					year: r.year,
					total_value: r.total_value || 0,
					n_contracts: r.n_contracts || 0,
					n_vendors: r.n_vendors || 0
				});
			}
		}
		return Array.from(byRegion.values());
	}

	$: activeRows = aggregateByRegion(
		(aggData[selectedGeometry] || []).filter(
			(r) =>
				r.year === selectedYear &&
				(selectedTier === NO_FILTER || r.tier === selectedTier) &&
				(selectedCluster === NO_FILTER || r.object_cluster === selectedCluster)
		)
	);

	$: console.log('FILTER DEBUG:', {
		geometry: selectedGeometry,
		selectedYear, selectedTier, selectedCluster,
		totalRowsForGeometry: (aggData[selectedGeometry] || []).length,
		activeRowsCount: activeRows.length,
		sampleRow: (aggData[selectedGeometry] || [])[0]
	});

	$: console.log('YEAR DEBUG:', { yearIndex, yearOptionsLength: yearOptions.length, yearOptions, selectedYear });

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
			const [cma, prov, world, locRes] = await Promise.all([
				fetch(`${base}/data/contracts_cma_agg.csv`).then((r) => r.text()),
				fetch(`${base}/data/contracts_prov_agg.csv`).then((r) => r.text()),
				fetch(`${base}/data/contracts_world_agg.csv`).then((r) => r.text()),
				fetch(`${base}/data/B1B2B3.csv`).then((r) => r.text())
			]);

			aggData.cma = parseAgg(cma);
			aggData.prov = parseAgg(prov);
			aggData.world = parseAgg(world);

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
	<TitleStandard title="Where does the Department of National Defence spend its contract dollars?" />
	<div class="text">
		<AuthorDate
			authors="<a href='https://schoolofcities.utoronto.ca/people/karen-chapple/' target='_blank'>Karen Chapple</a>, <a href='https://discover.research.utoronto.ca/8035-tara-vinodrai' target='_blank'>Tara Vinodrai</a>, <a href='https://www.linkedin.com/in/yihoi-jung-0b95351b5/' target='_blank'>Yihoi Jung</a>, <a href='https://www.linkedin.com/in/sarahbridgetgibbons/'>Sarah Gibbons</a>, Andrew Feng"
			date="Last updated July 28, 2026."
		/>
		<p>
			Department of National Defence (DND) contract disclosures show who the federal government pays for
			goods and services, and where those vendors are located. Contracts are classified into a defence-relevance
			tier and an industry cluster to help identify where defence-adjacent economic activity concentrates.
		</p>
	</div>

	{#if isLoading}
		<div class="status">Loading contract data…</div>
	{:else if loadError}
		<div class="status error">{loadError}</div>
	{:else}
		<div class="text" style="margin-bottom: 0px;">
			<div class="filter-row">
				<div class="filter-group">
					<span class="filter-label">Geography</span>
					<select class="year-select" bind:value={selectedGeometry}>
						{#each geometries as g}<option value={g.id}>{g.label}</option>{/each}
					</select>
				</div>

				<div class="filter-group">
					<span class="filter-label">Map style</span>
					<button class="toggle-btn" on:click={() => (darkMode = !darkMode)}>
						{darkMode ? 'Light' : 'Dark'}
					</button>
				</div>

				<div class="filter-group">
					<span class="filter-label">Tier</span>
					<select class="year-select" bind:value={selectedTier}>
						<option value={NO_FILTER}>All tiers</option>
						{#each tierOptions as t}<option value={t}>{t}</option>{/each}
					</select>
				</div>

				<div class="filter-group">
					<span class="filter-label">Industry cluster</span>
					<select class="year-select" bind:value={selectedCluster}>
						<option value={NO_FILTER}>All clusters</option>
						{#each clusterOptions as c}<option value={c}>{c}</option>{/each}
					</select>
				</div>

				<div class="filter-group">
					<span class="filter-label">Year</span>
					<div class="slider-row">
						<input
							type="range"
							min="0"
							max={yearOptions.length - 1}
							step="1"
							bind:value={yearIndex}
							class="year-slider"
						/>
						<span class="year-slider-value">{selectedYear ?? ''}</span>
					</div>
				</div>

				<div class="filter-group">
					<span class="filter-label">Metric</span>
					<select class="year-select" bind:value={metric}>
						<option value="value">Contract value</option>
						<option value="count">Number of contracts</option>
						<option value="vendors">Number of vendors</option>
					</select>
				</div>

				<div class="filter-group">
					<span class="filter-label">Military bases</span>
					<button class="toggle-btn" on:click={toggleMilitaryBases}>
						{showMilitaryBases ? 'Hide' : 'Show'}
					</button>
				</div>
			</div>
		</div>

		<section class="map-block">
			{#if selectedGeometry === 'cma'}
				<ContractsCmaCartogram
					rows={activeRows}
					{cmaGeojson}
					{provinceGeojson}
					{metric}
					{formatValue}
					{usGeojson}
					{darkMode}
					{militaryGeojson}
					{showMilitaryBases}
					{sizeBins}
				/>
			{:else if selectedGeometry === 'prov'}
				<ContractsProvinceCartogram
					rows={activeRows}
					{provinceGeojson}
					{metric}
					{formatValue}
					{usGeojson}
					{darkMode}
					{militaryGeojson}
					{showMilitaryBases}
					{sizeBins}
				/>
			{:else if selectedGeometry === 'world'}
				<ContractsWorldCartogram
					rows={activeRows}
					{worldGeojson}
					{metric}
					{formatValue}
					{darkMode}
					{militaryGeojson}
					{showMilitaryBases}
					{sizeBins}
				/>
			{/if}
		</section>


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

	<div class="text" style="margin-bottom: 0px;">
		<h3>Data sources and methods</h3>
		<p>
			Contract data comes from the <a href="https://search.open.canada.ca/contracts/?owner_org=dnd-mdn&page=1&sort=contract_date+desc">Government of Canada's disclosure of contracts over $10,000</a>,
			filtered to contracts issued by National Defence.
		</p>
		<p>
			Each contract is classified into a defence-relevance <b>tier</b> (Core Defence Industrial Complex,
			Industrial and Technical Support, or General Government Support) and an industry <b>cluster</b> based
			on its economic object code.
		</p>
		<p>
			Vendor locations are geocoded from postal codes. Any rows with no Canadian province or CMA are
			excluded from the map view.
		</p>

		<p>
			Download data:
			<a href="{base}/data/contracts_cma_agg.csv" download>Census Metropolitan Areas</a> ·
			<a href="{base}/data/contracts_prov_agg.csv" download>Provinces</a>
		</p>
	</div>
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
