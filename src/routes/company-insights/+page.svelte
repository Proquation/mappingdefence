<script>
	import { onMount } from 'svelte';
	import { csvParse } from 'd3-dsv';
	import { base } from '$app/paths';

	import '$lib/assets/global-styles.css';
	import Logo from '$lib/LogoTop.svelte';
	import Footer from '$lib/Footer.svelte';
	import AuthorDate from '$lib/AuthorDate.svelte';
	import TitleStandard from '$lib/TitleStandard.svelte';
	import DefenceMap from '$lib/DefenceMap.svelte';
	import Password from '$lib/Password.svelte';
	import CmaBubbleMap from '$lib/CmaBubbleMap.svelte';
	import ProvinceCartogram from '$lib/ProvinceCartogram.svelte';

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

	// Per-geometry data + geojson caches
	const aggData = {}; // { csd: [...rows], cma: [...], prov: [...] }
	const geojsonCache = {};

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
			suppressed: r.suppressed === 'True' || r.suppressed === 'true'
		}));
	}

	async function loadData() {
		try {
			const [csd, cma, prov] = await Promise.all([
				fetch(`${base}/data/csd_agg.csv`).then((r) => r.text()),
				fetch(`${base}/data/cma_agg.csv`).then((r) => r.text()),
				fetch(`${base}/data/prov_agg.csv`).then((r) => r.text())
			]);
			aggData.csd = parseAgg(csd);
			aggData.cma = parseAgg(cma);
			aggData.prov = parseAgg(prov);

			// Year + NAICS options derived from the union of all rows
			const allRows = [...aggData.csd, ...aggData.cma, ...aggData.prov];
			yearOptions = [...new Set(allRows.map((r) => r.year))].sort((a, b) => a - b);
			selectedYear = yearOptions[yearOptions.length - 1];

			const naicsMap = new Map();
			allRows.forEach((r) => {
				if (!['ALL', 'PRIMARY', 'SECONDARY'].includes(r.NAICS6) && !naicsMap.has(r.NAICS6)) {
					naicsMap.set(r.NAICS6, { desc: r.NAICSD, type: r.defence_type });
				}
			});
			naicsOptions = [...naicsMap.entries()]
				.map(([code, { desc, type }]) => ({ code, desc, type }))
				.sort((a, b) => {
					// primary before secondary, then by code
					if (a.type !== b.type) return a.type === 'primary' ? -1 : 1;
					return a.code.localeCompare(b.code);
				});
		} catch (err) {
			console.error(err);
			loadError = 'Unable to load aggregated defence data.';
		} finally {
			isLoading = false;
		}
	}

	async function ensureGeojson(geom) {
		if (geojsonCache[geom]) return geojsonCache[geom];
		const file = {
			csd: 'csd_boundaries',
			cma: 'cma_boundaries',
			prov: 'province_boundaries'
		}[geom];
		const gj = await fetch(`${base}/geojson/${file}.geojson`).then((r) => r.json());
		geojsonCache[geom] = gj;
		return gj;
	}

	// Active geojson (reactive — only in the browser, never during SSR)
	let activeGeojson = null;
	$: if (mounted && selectedGeometry) {
		ensureGeojson(selectedGeometry).then((gj) => (activeGeojson = gj));
	}

	// Build { region_uid -> total_sales_M } for the active geometry/year/mode
	$: valueByUid = (() => {
		const rows = aggData[selectedGeometry] || [];
		const lookup = {};
		rows.forEach((r) => {
			if (r.year !== selectedYear) return;
			if (r.NAICS6 !== selectedMode) return;
			lookup[r.region_uid] = r.total_sales_M;
		});
		return lookup;
	})();

	// Build { region_uid -> {sales, n_firms, avg_employees} } for the active geometry/year/mode
	$: recordByUid = (() => {
		const rows = aggData[selectedGeometry] || [];
		const lookup = {};
		rows.forEach((r) => {
			if (r.year !== selectedYear) return;
			if (r.NAICS6 !== selectedMode) return;
			lookup[r.region_uid] = {
				sales: r.total_sales_M,
				n_firms: r.n_firms,
				avg_employees: r.avg_employees
			};
		});
		return lookup;
	})();

	$: maxValue = Math.max(
		1,
		...Object.values(recordByUid)
			.map((d) => d.sales)
			.filter((v) => Number.isFinite(v))
	);

	onMount(() => {
		mounted = true;
		loadData();
	});
</script>

<Password />

<Logo logoType="Blue" backgroundColor="var(--brandWhite)" />

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
			This map aggregates defence-related firm sales into Canadian geographies and shades each region from
			light to dark by total sales. Use the filters to choose the geography, the defence category, and the
			year.
		</p>
		<p>
			Note: Any geometry with only 1 firm has been excluded for privacy. The total sales reflect the firms shown.
		</p>
	</div>

	{#if isLoading}
		<div class="status">Loading defence sales data...</div>
	{:else if loadError}
		<div class="status error">{loadError}</div>
	{:else}
		<div class="text" style="margin-bottom: 0px;">
			<h3>Filter the map</h3>
			<div class="filter-row">
				<div class="filter-group">
					<span class="filter-label">Aggregate by</span>
					<select class="year-select" bind:value={selectedGeometry}>
						{#each geometries as g}
							<option value={g.id}>{g.label}</option>
						{/each}
					</select>
				</div>

				<div class="filter-group">
					<span class="filter-label">Show</span>
					<select class="year-select" bind:value={selectedMode}>
						<option value="ALL">All defence</option>
						<option value="PRIMARY">Primary only</option>
						<option value="SECONDARY">Secondary only</option>
						<optgroup label="Primary NAICS">
							{#each naicsOptions.filter((n) => n.type === 'primary') as n}
								<option value={n.code} class="opt-primary">{n.code} — {n.desc}</option>
							{/each}
						</optgroup>
						<optgroup label="Secondary NAICS">
							{#each naicsOptions.filter((n) => n.type === 'secondary') as n}
								<option value={n.code} class="opt-secondary">{n.code} — {n.desc}</option>
							{/each}
						</optgroup>
					</select>
				</div>

				<div class="filter-group">
					<span class="filter-label">Year</span>
					<select class="year-select" bind:value={selectedYear}>
						{#each yearOptions as year}
							<option value={year}>{year}</option>
						{/each}
					</select>
				</div>
			</div>
		</div>

		<section class="map-block">
			<DefenceMap geojson={activeGeojson} {recordByUid} {maxValue} {formatSales} />
		</section>

		<!-- <section class="map-block">
			<CmaBubbleMap cmaGeojson={}/>
		</section>

		<section class="map-block">
			<ProvinceCartogram/>
		</section> -->
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
		gap: 8px;
		margin-bottom: 16px;
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
		color: var(--brandGray90);
	}

	.year-select {
		max-width: 280px;
		padding: 6px 10px;
		border: 1px solid var(--brandGray);
		border-radius: 5px;
		background: var(--brandWhite);
		color: var(--brandGray90);
		font-family: OpenSans;
		font-size: 13px;
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