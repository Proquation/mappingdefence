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

	// let yearOptions = [];
	// let clusterOptions = [];
	// let tierOptions = [];

	let metric = 'value'; // 'value' | 'count' | 'vendors'

	// Per-geometry data + geojson caches
	
	const geojsonCache = {};

	let aggDataCma = [];
	let aggDataProv = [];
	let aggDataWorld = [];


	let yearIndex = 0;
	let selectedYear = 'ALL'; 

	const NO_FILTER = '__ANY__';

	let selectedTier = NO_FILTER;
	let selectedCluster = NO_FILTER;

	// $: {
	// 	if (aggData[selectedGeometry] && aggData[selectedGeometry].length > 0) {
	// 		const data = aggData[selectedGeometry];
	// 		const years = [...new Set(data.map(r => r.year))].sort();
	// 		const tiers = [...new Set(data.map(r => r.tier))]
	// 			.filter(t => Boolean(t) && t !== 'ALL')  // exclude the rollup pseudo-tier
	// 			.sort();

	// 		const clusters = [...new Set(data.map(r => r.object_cluster))]
	// 			.filter(c => Boolean(c) && c !== 'ALL')
	// 			.sort();

	// 		yearOptions = years;
	// 		tierOptions = tiers;
	// 		clusterOptions = clusters;
			
	// 		// Reset year if needed
	// 		if (yearIndex >= years.length) {
	// 			yearIndex = 0;
	// 		}
	// 		if (years.length > 0) {
	// 			selectedYear = years[yearIndex];
	// 		}
	// 	}
	// }
	$: currentAggData = selectedGeometry === 'cma' ? aggDataCma
		: selectedGeometry === 'prov' ? aggDataProv
		: aggDataWorld;

	$: yearOptions = currentAggData?.length
		? ['ALL', ...[...new Set(currentAggData.map(r => r.year))].sort()]
		: ['ALL'];

	$: tierOptions = currentAggData?.length
		? [...new Set(currentAggData.map(r => r.tier))].filter(t => t && t !== 'ALL').sort()
		: [];

	$: clusterOptions = currentAggData?.length
		? [...new Set(currentAggData.map(r => r.object_cluster))].filter(c => c && c !== 'ALL').sort()
		: [];


	$: if (selectedGeometry === 'world' && selectedYear === 2021) {
		const rawRows = aggDataWorld.filter(r => r.region_name === 'Sri Lanka' && r.year === 2021);
		console.log('SRI LANKA 2021 RAW ROWS:', rawRows);
	}

	$: sizeBins =
		metric === 'count' ? computeSizeBins(filteredAllYears, 'n_contracts')
		: metric === 'vendors' ? computeSizeBins(filteredAllYears, 'n_vendors')
		: computeSizeBins(filteredAllYears, 'total_value');

	$: sizeBinsAllYearsView =
		metric === 'count' ? computeSizeBins(activeRows, 'n_contracts')
		: metric === 'vendors' ? computeSizeBins(activeRows, 'n_vendors')
		: computeSizeBins(activeRows, 'total_value');

	$: effectiveSizeBins = selectedYear === 'ALL' ? sizeBinsAllYearsView : sizeBins;


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
			year: r.year === 'ALL' ? 'ALL' : Number(r.year),  // ← preserve ALL
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

	
	$: filteredAllYears = (currentAggData || []).filter((r) => {
		const tierMatch = selectedTier === NO_FILTER ? r.tier === 'ALL' : r.tier === selectedTier;
		const clusterMatch = selectedCluster === NO_FILTER ? r.object_cluster === 'ALL' : r.object_cluster === selectedCluster;
		return tierMatch && clusterMatch;
	});


	$: {
		if (aggDataCma.length > 0 && cmaGeojson) {
			const dataIds = new Set(aggDataCma.map(r => r.region_uid));
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
	// $: sizeBins =
	// 	metric === 'count' ? computeSizeBins(filteredAllYears, 'n_contracts')
	// 	: metric === 'vendors' ? computeSizeBins(filteredAllYears, 'n_vendors')
	// 	: computeSizeBins(filteredAllYears, 'total_value');

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
			ensureGeojson('world_countries').then((g) => (worldGeojson = g));
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
		(currentAggData || []).filter((r) => {
			const tierMatch = selectedTier === NO_FILTER ? r.tier === 'ALL' : r.tier === selectedTier;
			const clusterMatch = selectedCluster === NO_FILTER ? r.object_cluster === 'ALL' : r.object_cluster === selectedCluster;
			const yearMatch = selectedYear === 'ALL' ? r.year === 'ALL' : r.year === selectedYear;
			return yearMatch && tierMatch && clusterMatch;
		})
	);

	$: console.log('FILTER DEBUG:', {
		geometry: selectedGeometry,
		selectedYear, selectedTier, selectedCluster,
		totalRowsForGeometry: (currentAggData || []).length,
		activeRowsCount: activeRows.length,
		sampleRow: (currentAggData || [])[0]
	});

	$: {
		const numericYears = yearOptions.filter(y => y !== 'ALL');
		yearIndex; // reference to establish dependency
		if (selectedYear !== 'ALL') {
			selectedYear = numericYears[yearIndex] ?? 'ALL';
		}
	}	

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

			aggDataCma = parseAgg(cma);
			aggDataProv = parseAgg(prov);
			aggDataWorld = parseAgg(world);

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
	<!-- ALTERNATIVE TITLE Contract based procurement efforts by the Department of National Defence -->
	<TitleStandard title="Explore where Canadian defence firms are benefitting from national contracts and selling their products." /> 
	<div class="text">
		<AuthorDate
			authors="<a href='https://schoolofcities.utoronto.ca/people/karen-chapple/' target='_blank'>Karen Chapple</a>, <a href='https://discover.research.utoronto.ca/8035-tara-vinodrai' target='_blank'>Tara Vinodrai</a>, <a href='https://www.linkedin.com/in/yihoi-jung-0b95351b5/' target='_blank'>Yihoi Jung</a>, <a href='https://www.linkedin.com/in/sarahbridgetgibbons/'>Sarah Gibbons</a>, Andrew Feng"
			date="Last updated August 4th, 2026."
		/>
		<p>
			Department of National Defence (DND) contract disclosures show who the federal government pays for
			goods and services, and where those vendors are located. Contracts are classified into tiers based on whether they come from core defence sectors, 
			provide general government support, or industrial and technical support. 
			The map also displays the location of defense-related industrial sectors across the country, as well as Canadian Forces bases. 

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
					<button class="toggle-btn" class:selected={!darkMode} on:click={() => (darkMode = !darkMode)}>
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
					<span class="filter-label">Industry sector</span>
					<select class="year-select" bind:value={selectedCluster}>
						<option value={NO_FILTER}>All sectors</option>
						{#each clusterOptions as c}<option value={c}>{c}</option>{/each}
					</select>
				</div>

				<div class="filter-group">
					<span class="filter-label">Year</span>
					<div class="slider-row">
						<button class="toggle-btn" class:selected={selectedYear === 'ALL'}
							on:click={() => selectedYear = 'ALL'}>
							All years
						</button>
						<input
							type="range"
							min="0"
							max={yearOptions.filter(y => y !== 'ALL').length - 1}
							step="1"
							bind:value={yearIndex}
							class="year-slider"
							on:input={() => selectedYear = yearOptions.filter(y => y !== 'ALL')[yearIndex]}
						/>
						<span class="year-slider-value"
							on:click={() => selectedYear = yearOptions.filter(y => y !== 'ALL')[yearIndex]}
							style="cursor:pointer; opacity:{selectedYear === 'ALL' ? 0.4 : 1}">
							{yearOptions.filter(y => y !== 'ALL')[yearIndex] ?? ''}
						</span>
					</div>
				</div>

				<!-- <div class="filter-group">
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
				</div> -->

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
					<button class="toggle-btn" class:selected={showMilitaryBases} on:click={toggleMilitaryBases}>
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
					sizeBins = {effectiveSizeBins}
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
					sizeBins = {effectiveSizeBins}
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
					sizeBins = {effectiveSizeBins}
				/>
			{/if}
		</section>


	{/if}

	<div class="text">

		<p>
			Contract data comes from the Public Services and Procurement Canada’s (PSPC) <a href=" https://search.open.canada.ca/contracts/">disclosure of contracts over $10,000</a>, filtered to contracts issued by the Department of National Defence. 
		</p>

		<p>
			Because contracts are frequently amended, a single procurement can appear multiple times in the raw disclosure records. We retain only the most recent amendment for each unique Procurement Identification Number before analysis.
		</p>
		<p>
			Total Contract Value figures for multi-year contracts reflect the full contracted value rather than annual spending. As such, the year-over-year figures represent the value of the contracts issued in that year, rather than annual defence expenditures or the pace at which funds were disbursed. 
		</p>

		<h3>
			Classifying contracts by their relationship to defence capability 
		</h3>

		<p>
			We sort every contract into one of three tiers, based on its economic object code, to capture how closely a contract's purpose is tied to military capability rather than simply to defence-department spending.
		</p>

		<p>
			Core Defence contracts carry an object code tied to the provision and production of defence goods and services, and directly generate, sustain, or enhance military operational capability. This can look like weapons systems, military platforms (aircraft, ships, vehicles), and specialized defence infrastructure.
		</p>

		<p>
			Technical Support contracts enable defence production, maintenance, and logistics, but don't themselves constitute military capability: engineering services, fuel, and IT support are typical examples. These are goods and services that could exist outside a defence context, but here are supporting defence activities specifically.
		</p>

		<p>
			General Government Support contracts are the least tied to defence capability. These are the costs of operating the Department of National Defence as a government organization, rather than producing military capability. 
		</p>

		<h3>
			What the data tells us about the landscape of DND Procurement 
		</h3>

		<p>
			Although Canadian defence procurement touches a wide range of places, spending within each tier is heavily concentrated in a small number of urban centres. Looking at contracts with Canadian vendors between 2017 and 2026, the top five CMAs account for the large majority of each tier's total value, even though many more CMAs and CAs receive at least some contracting activity.
		</p>
		<p>
			The Core Defence Industrial Complex shows the sharpest concentration: the top five CMAs capture 88.6% of the tier's total value, even though 95 different CMAs and CAs appear somewhere in the data. General Government Support is somewhat less concentrated, with the top five CMAs accounting for 83.0% of value spread across 144 places, while Industrial and Technical Support falls in between, with the top five capturing 85.0% of value across 139 places.

		</p>
		<p>
			Halifax dominates the Core Defence tier, accounting for 44% of the national contract value from 2017-2026. It is followed by Montréal (20%), Vancouver (16%), Québec City (5%), and Ottawa–Gatineau (4%). 
		</p>

		<p>
			For the industrial and technical support tier, the most dominant city is Ottawa-Gatineau with 26% of the national share of contract value, followed closely by Montreal (24%), then Halifax (8%), Toronto (7%), and Calgary (2%).
		</p>
		
		<p>
			Finally, for administrative-focused contracts, the leader is Ottawa-Gatineau with 60% of the national share, followed by Montreal (7%), Toronto (6%), Calgary (4%), and Halifax (2%).

		</p>

		<h3>
			What Sectors Are Being Contracted, and Where?
		</h3>

		<p>
			The federal government has signalled a major expansion in defence spending: $180 billion in defence procurement opportunities and $290 billion in defence-related capital investment. This increase will touch every tier of the defence industrial base, but not evenly. Some tiers are positioned to see larger impacts than others, and the same is true across sectors [no source for this– does it need one?]. The government has already flagged certain sectors as priority growth areas, including nitrocellulose production and the promotion of AI and quantum technologies. Understanding which regions dominate specific sectors may provide insight into where future sector-specific investments are likely to flow. 

		</p>

		<p>
			PLACEHOLDER FOR CHART -- see the doc: https://docs.google.com/document/d/1jQz2MjrjpoqQVzX3HbreUsS1DIRVKdTg9IU2fLX-JzE/edit?tab=t.0
		</p>

		<p>
			Halifax's dominance can be largely attributed to its shipbuilding industry, receiving exactly half of the value of all marine-related contracts from DND over the analysis period. In 2026, Irving Shipbuilding Inc. received multibillion-dollar contracts to construct a fleet of River-class destroyers to replace Canada's aging naval fleet. These investments are already having significant impacts on the local community. As the company seeks to hire skilled workers to support production, it is facing labour shortages, while training programs for key trades such as welding are already operating at capacity. 
		</p>

		<p>
			PLACEHOLDER FOR CHART -- see the doc: https://docs.google.com/document/d/1jQz2MjrjpoqQVzX3HbreUsS1DIRVKdTg9IU2fLX-JzE/edit?tab=t.0
		</p>

		<p>
			Montreal features strongly across many sectors, and makes up the largest single CMA share of the aerospace and space industry (46.5%). This reflects Montreal's broader position in the industry: the city is the third-largest centre of aerospace manufacturing in the world, and aerospace remains Quebec's largest export sector. Despite this clustering, more DND money in aerospace flowed to foreign vendors than to Montreal itself. Montreal's largest DND contract shares are actually in Land Systems & Vehicles (71.0%) and Weapons (62.5%).
		</p>

		<p>
			Administrative services (70.0%), Communications & Electronics (65.1%), and Digital Systems & Software (60.7%) are the sectors with contracts overwhelmingly awarded to vendors in the Ottawa region. This is consistent with a few plausible explanations. Proximity to the federal government, and the familiarity with government procurement processes that comes with it, likely makes Ottawa-based vendors an attractive choice for DND. Ottawa's established technology cluster, built up over decades of public-sector contracting, reinforces this advantage further. However, Ottawa’s advantage does not occur in all defence-related sectors, making up a minority of sectors like Aerospace & Space or Automotive & Heavy Vehicles.
		</p>

		<h3>
			Takeaways
		</h3>

		<p>
			Taken together, these patterns suggest that new defence spending is unlikely to be distributed evenly across the country if future investment follows the same channels as the contracts already awarded. Whether this pattern reflects genuine advantages in relevant industrial capacity, the advantages of being an established and familiar vendor to DND, or a market with very few qualified domestic suppliers to begin with is a more difficult question. 
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
	.toggle-btn.selected {
		background: #ffffff;
		color: #000000;
		border-color: #ffffff;
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
