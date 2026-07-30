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
	let selectedTier = 'ALL';
	// object_cluster: "ALL" | one of the 14 clusters
	let selectedCluster = 'ALL';

	let yearOptions = [];
	let clusterOptions = [];
	let tierOptions = [];

	let metric = 'value'; // 'value' | 'count' | 'vendors'

	// Per-geometry data + geojson caches
	const aggData = {}; // { cma: [...rows], prov: [...] }
	const geojsonCache = {};

	let yearIndex = 0;
	let selectedYear = null; 

	$: {
		if (aggData[selectedGeometry] && aggData[selectedGeometry].length > 0) {
			const data = aggData[selectedGeometry];
			const years = [...new Set(data.map(r => r.year))].sort();
			const tiers = [...new Set(data.map(r => r.tier))].filter(Boolean).sort();
			const clusters = [...new Set(data.map(r => r.object_cluster))].filter(Boolean).sort();
			
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

	function parseAgg(csvText) {
		return csvParse(csvText).map((r) => ({
			region_uid: String(r.region_uid).trim(),
			region_name: r.region_name,
			year: Number(r.year),
			tier: r.tier,
			object_cluster: r.object_cluster,
			total_value: r.total_value === '' ? null : Number(r.total_value),
			n_contracts: r.n_contracts === '' ? null : Number(r.n_contracts),
			n_vendors: r.n_vendors === '' ? null : Number(r.n_vendors)
		}));
	}

	async function loadData() {
		console.time('loadData: total');
		try {
			
			const [cma, prov] = await Promise.all([
				fetch(`${base}/data/contracts_cma_agg.csv`).then((r) => r.text()),
				fetch(`${base}/data/contracts_prov_agg.csv`).then((r) => r.text())
			]);

			aggData.cma = parseAgg(cma);
			aggData.prov = parseAgg(prov);
			aggData.world = parseAgg(world);

			console.log('CMA rows:', aggData.cma.length, 'Prov rows:', aggData.prov.length, 'World rows:', aggData.world.length);

		} finally {
			isLoading = false;
			console.timeEnd('loadData: total');
		}
	}

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

	$: activeRows = (aggData[selectedGeometry] || []).filter(
		(r) =>
			r.year === selectedYear &&
			r.tier === selectedTier &&
			r.object_cluster === selectedCluster
	);

	$: console.log('FILTER DEBUG:', {
		geometry: selectedGeometry,
		selectedYear, selectedTier, selectedCluster,
		totalRowsForGeometry: (aggData[selectedGeometry] || []).length,
		activeRowsCount: activeRows.length,
		sampleRow: (aggData[selectedGeometry] || [])[0]
	});

	$: console.log('YEAR DEBUG:', { yearIndex, yearOptionsLength: yearOptions.length, yearOptions, selectedYear });
	
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
						<option value="ALL">All tiers</option>
						{#each tierOptions as t}<option value={t}>{t}</option>{/each}
					</select>
				</div>

				<div class="filter-group">
					<span class="filter-label">Industry cluster</span>
					<select class="year-select" bind:value={selectedCluster}>
						<option value="ALL">All clusters</option>
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
				/>
			{/if}
		</section>
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
