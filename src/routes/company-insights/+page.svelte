<script>
	import { onMount } from 'svelte';
	import { csvParse } from 'd3-dsv';
	import { base } from '$app/paths';

	import '$lib/assets/global-styles.css';
	import Logo from '$lib/LogoTop.svelte';
	import Footer from '$lib/Footer.svelte';
	import AuthorDate from '$lib/AuthorDate.svelte';
	import TitleStandard from '$lib/TitleStandard.svelte';
	import Password from '$lib/Password.svelte';
	import DefenceMap from '$lib/DefenceMap.svelte';
	import CmaCartogram from '$lib/CmaCartogram.svelte';
	import ProvinceCartogram from '$lib/ProvinceCartogram.svelte';
	import RankingTables from '$lib/RankingTables.svelte';

	let isLoading = true;
	let loadError = '';
	let mounted = false;

	// Geometry selection
	const geometries = [
		{ id: 'csd', label: 'Census Subdivision' },
		{ id: 'cma', label: 'Census Metropolitan Area' },
		{ id: 'prov', label: 'Province' }
	];
	let selectedGeometry = 'cma';

	// Mode: ALL / PRIMARY / SECONDARY / a specific NAICS6 code
	let selectedMode = 'ALL';
	let selectedYear = null;
	let yearOptions = [];
	let naicsOptions = []; // [{code, desc}] of individual NAICS codes

	let lqBasis = 'jobs'; // sales vs. firms vs. jobs
	let colourType = 'lq';   // 'lq' | 'totals'

	// Per-geometry data + geojson caches
	const aggData = {}; // { csd: [...rows], cma: [...], prov: [...] }
	const geojsonCache = {};

	let compareYear = null;


	let usGeojson = null;
	let darkMode = true;

	let militaryGeojson = null;
	let showMilitaryBases = false;
	let militaryTypeFilter = new Set(['Canadian Army', 'Royal Canadian Airforce', 'Royal Canadian Navy', 'All Services']);

	async function ensureMilitaryGeojson() {
		if (militaryGeojson) return;
		militaryGeojson = await fetch(`${base}/geojson/military_bases_ca.geojson`).then(r => r.json());
	}

	function toggleMilitaryBases() {
		showMilitaryBases = !showMilitaryBases;
		if (showMilitaryBases) ensureMilitaryGeojson();
	}


	function formatSales(value) {
		if (!Number.isFinite(value)) return 'N/A';
		if (value >= 1000) return `$${(value / 1000).toFixed(2)}B`;
		return `$${value.toFixed(1)}M`;
	}

	function parseAgg(csvText) {
		return csvParse(csvText).map((r) => ({
			region_uid: String(r.region_uid).trim(),
			region_name: r.region_name,
			year: Number(r.year),
			NAICS6: String(r.NAICS6).trim(),
			NAICSD: r.NAICSD,
			defence_type: r.defence_type,
			total_sales_M: r.total_sales_M === '' ? null : Number(r.total_sales_M),
			sales_bucket: r.sales_bucket,
			n_firms: r.n_firms,
			avg_employees: r.avg_employees === '' ? null : Number(r.avg_employees),
			total_jobs: r.total_jobs === '' ? null: Number(r.total_jobs),
			lq_sales: r.lq_sales === '' || r.lq_sales == null ? null : Number(r.lq_sales),
			lq_firms: r.lq_firms === '' || r.lq_firms == null ? null : Number(r.lq_firms),
			lq_jobs: r.lq_jobs === '' || r.lq_jobs == null ? null : Number(r.lq_jobs),
			suppressed: r.suppressed === 'True' || r.suppressed === 'true'
		}));
	}


	async function loadData() {
		try {
			const [csd, cmaRural, prov] = await Promise.all([
				fetch(`${base}/data/csd_agg.csv`).then((r) => r.text()),
				fetch(`${base}/data/cma_rural_agg.csv`).then((r) => r.text()),
				fetch(`${base}/data/prov_agg.csv`).then((r) => r.text())
			]);
			aggData.csd = parseAgg(csd);
			aggData.cma = parseAgg(cmaRural);   // bubble view uses the rural-aware file
			aggData.prov = parseAgg(prov);
 
			const allRows = [...aggData.csd, ...aggData.cma, ...aggData.prov];
			yearOptions = [...new Set(allRows.map((r) => r.year))].sort((a, b) => a - b);
			selectedYear = yearOptions[yearOptions.length - 1];
			compareYear = yearOptions[yearOptions.length - 2] ?? yearOptions[0];
 
			const naicsMap = new Map();
			allRows.forEach((r) => {
				if (!['ALL', 'PRIMARY', 'SECONDARY'].includes(r.NAICS6) && !naicsMap.has(r.NAICS6)) {
					naicsMap.set(r.NAICS6, { desc: r.NAICSD, type: r.defence_type });
				}
			});
			naicsOptions = [...naicsMap.entries()]
				.map(([code, { desc, type }]) => ({ code, desc, type }))
				.sort((a, b) => (a.type !== b.type ? (a.type === 'primary' ? -1 : 1) : a.code.localeCompare(b.code)));
		} catch (err) {
			console.error(err);
			loadError = 'Unable to load aggregated defence data.';
		} finally {
			isLoading = false;
		}
	}


	async function ensureGeojson(file) {
		if (geojsonCache[file]) return geojsonCache[file];
		const gj = await fetch(`${base}/geojson/${file}.geojson`).then((r) => r.json());
		geojsonCache[file] = gj;
		return gj;
	}

	let csdGeojson = null, cmaGeojson = null, provinceGeojson = null, provinceSimple = null;
	$: if (mounted) {
		if (selectedGeometry === 'csd') {
			ensureGeojson('csd_boundaries').then((g) => (csdGeojson = g));
			ensureGeojson('province-boundaries-simple').then((g) => (provinceGeojson = g)); // ← add
			ensureGeojson('us_nation').then((g) => (usGeojson = g));
		}
		if (selectedGeometry === 'cma') {
			ensureGeojson('cma_boundaries').then((g) => (cmaGeojson = g));
			ensureGeojson('province-boundaries-simple').then((g) => (provinceGeojson = g));
			ensureGeojson('us_nation').then((g) => (usGeojson = g));
		}
	}


	$: activeRows = (aggData[selectedGeometry] || []).filter(
		(r) => r.year === selectedYear && r.NAICS6 === selectedMode
	);

	$: compareRows = (aggData[selectedGeometry] || []).filter(
		(r) => r.year === compareYear && r.NAICS6 === selectedMode
	);
 
	$: recordByUid = (() => {
		const lookup = {};
		const lqKey = { sales: 'lq_sales', firms: 'lq_firms', jobs: 'lq_jobs' }[lqBasis];
		activeRows.forEach((r) => {
			const absVal = lqBasis === 'sales' ? r.total_sales_M
						: lqBasis === 'jobs'  ? r.total_jobs
						: (r.suppressed ? null : Number(r.n_firms) || null);
			lookup[r.region_uid] = {
				sales: r.total_sales_M,
				n_firms: r.n_firms,
				total_jobs: r.total_jobs,
				avg_employees: r.avg_employees,
				lq: r[lqKey],
				absVal              // the raw value for the active basis
			};
		});
		return lookup;
	})();
	

	onMount(() => {
		mounted = true;
		loadData();
	});
</script>

<!-- <Password /> -->

<Logo logoType="White" backgroundColor="var(--brandGray90)"/>

<main class="page">
	<TitleStandard title="Where are defence industry sales concentrated in Canada?" />
	<div class="text">
		<AuthorDate
			authors="<a href='https://schoolofcities.utoronto.ca/people/karen-chapple/' target='_blank'>Karen Chapple</a>, <a href='https://discover.research.utoronto.ca/8035-tara-vinodrai' target='_blank'>Tara Vinodrai</a>, <a href='https://www.linkedin.com/in/yihoi-jung-0b95351b5/' target='_blank'>Yihoi Jung</a>, <a href='https://www.linkedin.com/in/sarahbridgetgibbons/'>Sarah Gibbons</a>, Andrew Feng</AuthorDate>"
			date="May 2026."
		/>
		<p>
			Defence spending in Canada has historically been difficult to gather. Canada has historically kept
			defence spending quite low. Recent commitments from the Federal Budget 2025 are to spend $30B in
			defence over 5 years and to reach 5% of gross domestic product (GDP) spending in defence by 2035.
			However, it isn't clear as to what the fiscal breakdown is like in what and who they will invest in.
			This tool aims to tackle historical defence spending based on company sales using the North American
			Industry Classification System (NAICS).
		</p>
		<p>
			This tool aggregates defence-related firms' sales and employees into different Canadian geographies.
			Switch the geography to view provinces, census metropolitan areas and their rural counterparts as cartograms (size = sales, colour = location quotient), and census subdivisions as choropleths.
		</p>
		<p>
			Note: Any geometry with only 1 firm has been excluded for privacy. The total values reflect those that have been included only.
		</p>
	</div>

	{#if isLoading}
		<div class="status">Loading defence sales data...</div>
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
					<button class="toggle-btn" on:click={() => darkMode = !darkMode}>
						{darkMode ? 'Light' : 'Dark'}
					</button>
				</div>
 
				<div class="filter-group">
					<span class="filter-label">Show</span>
					<select class="year-select" bind:value={selectedMode}>
						<option value="ALL">All defence</option>
						<option value="PRIMARY">Primary only</option>
						<option value="SECONDARY">Secondary only</option>
						<optgroup label="Primary NAICS">
							{#each naicsOptions.filter((n) => n.type === 'primary') as n}
								<option value={n.code}>{n.code} — {n.desc}</option>
							{/each}
						</optgroup>
						<optgroup label="Secondary NAICS">
							{#each naicsOptions.filter((n) => n.type === 'secondary') as n}
								<option value={n.code}>{n.code} — {n.desc}</option>
							{/each}
						</optgroup>
					</select>
				</div>
 
				<div class="filter-group">
					<span class="filter-label">Year</span>
					<select class="year-select" bind:value={selectedYear}>
						{#each yearOptions as year}<option value={year}>{year}</option>{/each}
					</select>
				</div>
 
				{#if selectedGeometry === 'cma' || selectedGeometry === 'prov' || selectedGeometry === 'csd'}
					<div class="filter-group">
						<span class="filter-label">Metric</span>
						<select class="year-select" bind:value={lqBasis}>
							<option value="sales">Sales</option>
							<option value="firms">Firms</option>
							<option value="jobs">Jobs</option>
						</select>
					</div>

					<div class="filter-group">
						<span class="filter-label">Colour by metric type</span>
						<select class="year-select" bind:value={colourType}>
							<option value="totals">Totals</option>
							<option value="lq">Location Quotients</option>
						</select>
					</div>

					<div class="filter-group">
						<span class="filter-label">Military bases</span>
						<button class="toggle-btn" on:click={toggleMilitaryBases}>
							{showMilitaryBases ? 'Hide' : 'Show'}
						</button>
					</div>
				{/if}
			</div>
		</div>
 
		<section class="map-block">
			{#if selectedGeometry === 'csd'}
				<DefenceMap geojson={csdGeojson} {recordByUid} {lqBasis} {colourType} {formatSales} {provinceGeojson} {usGeojson} {darkMode} {militaryGeojson} {showMilitaryBases}/>
			{:else if selectedGeometry === 'cma'}
				<CmaCartogram rows={activeRows} {cmaGeojson} {provinceGeojson} {lqBasis} {colourType} {formatSales} {usGeojson} {darkMode} {militaryGeojson} {showMilitaryBases}/>
			{:else}
				<ProvinceCartogram rows={activeRows} compareRows = {compareRows} {provinceGeojson} {lqBasis} {colourType} {formatSales} {usGeojson} {darkMode} {militaryGeojson} {showMilitaryBases}/>
			{/if}
		</section>
		<RankingTables
		csdRows={aggData.csd || []} cmaRows={aggData.cma || []} provRows={aggData.prov || []}
		{lqBasis} {colourType} {selectedYear} {selectedMode} {selectedGeometry} {formatSales} />
	{/if}


	<div class="text" style="margin-bottom: 0px;">
		<h3>Data sources and methods</h3>
		<p>
			The company sales volume data is from the <a
				href="https://mdl.library.utoronto.ca/technology/tutorials/working-data-axle-historical-business-location-data"
				>University of Toronto Library Data Axle</a
			>. In order to identify the companies we wanted to observe from the historical business dataset, we
			gathered a list of NAICS codes deemed to be at least partially defence related.
		</p>
		<p>
			"Primary defence" is deemed as NAICS codes where the companies' sales are their primarily
			defence-related. "Secondary defence" is when defence is not the primary product that these companies
			produce. For example, engineering services fall under many different sectors, but companies like <a
				href="https://www.wsp.com/en-me/sectors/defense">Williams Sale Partnership (WSP)</a
			> span dozens of different sectors, one of them being defence.
		</p>
		<p>
			To protect firm-level confidentiality, regions with fewer than three firms in a given category and
			year have their exact sales suppressed and appear as "no data" on the map.
		</p>

		<p>
			Download data:
			<a href="{base}/data/csd_agg.csv" download>Census Subdivisions</a> ·
			<a href="{base}/data/cma_rural_agg.csv" download>Census Metropolitan Areas</a> ·
			<a href="{base}/data/prov_agg.csv" download>Provinces</a>
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
		/* gap: 8px; */
		/* margin-bottom: 16px; */
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

	.year-select option,
	.year-select optgroup {
		background: var(--brandGray90);
		color: var(--brandWhite);
	}

	.year-select :global(option.opt-primary) {
		background-color: #e3f0f7; /* light blue */
	}
	.year-select :global(option.opt-secondary) {
		background-color: #fbe4e4; /* light red */
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