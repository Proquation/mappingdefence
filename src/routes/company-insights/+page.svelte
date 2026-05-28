

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

	const naicsPalette = [
		'--brandDarkBlue',
		'--brandMedBlue',
		'--brandLightBlue',
		'--brandPurple',
		'--brandPink',
		'--brandDarkGreen',
		'--brandMedGreen',
		'--brandLightGreen',
		'--brandRed',
		'--brandYellow',
		'--brandOrange',
		'--brandGray70'
	];

	// Define codes for the "Secondary" category (e.g., dual-use like engineering and optical instruments)
	// Any code not in this list is treated as "Primary"
	const secondaryNaicsCodes = ['541330', '333314'];

	const naicsColorOverrides = {
		'541330': '--brandRed',
		'332992': '--brandDarkBlue',
		'332994': '--brandMedBlue',
		'333314': '--brandLightBlue',
		'334511': '--brandPink',
		'336411': '--brandYellow',
		'336414': '--brandOrange',
		'336992': '--brandMedGreen'
	};

	let isLoading = true;
	let loadError = '';
	let rawData = [];
	let filteredData = [];
	let naicsOptions = [];
	let naicsLabelByCode = {};
	let provinceOptions = [];
	let yearOptions = [];
	let selectedNaics = [];
	let selectedProvinces = [];
	const allYearsLabel = 'All years';
	let selectedYear = allYearsLabel;
	let colorByNaics = {};
	let maxSales = 1;

	const minRadius = 3;
	const maxRadius = 28;

	function formatSales(value) {
		if (!Number.isFinite(value)) return 'N/A';
		if (value >= 1000) return `${(value / 1000).toFixed(2)}B`;
		return `${value.toFixed(1)}M`;
	}

	function formatEmployees(value) {
		if (!Number.isFinite(value)) return 'N/A';
		if (value >= 1000) return `${(value / 1000).toFixed(1)}K`;
		return `${value.toFixed(0)}`;
	}

	function mean(values) {
		if (!values.length) return 0;
		return values.reduce((sum, value) => sum + value, 0) / values.length;
	}

	function median(values) {
		if (!values.length) return 0;
		const sorted = [...values].sort((a, b) => a - b);
		const mid = Math.floor(sorted.length / 2);
		if (sorted.length % 2 === 0) return (sorted[mid - 1] + sorted[mid]) / 2;
		return sorted[mid];
	}

	function sizeToPixels(value) {
		const safeMax = Math.max(1, maxSales);
		const t = Math.sqrt(Math.max(0, value)) / Math.sqrt(safeMax);
		return minRadius + (maxRadius - minRadius) * t;
	}

	function resolveCssColor(token) {
		if (typeof document === 'undefined') return token;
		if (token?.startsWith('--')) {
			const value = getComputedStyle(document.documentElement).getPropertyValue(token).trim();
			return value || '#999999';
		}
		return token;
	}

	function parseRow(row) {
		const lat = Number(row.lat);
		const lon = Number(row.long);
		const sales = Number(row.sales_M);
		const employees = Number(row.employees);
		const year = Number(row.year);
		const naicsCode = String(row.NAICS6 || '').trim();
		const naicsDesc = String(row.NAICSD || '').trim();
		const province = String(row.STATE || '').trim();
		const city = String(row.STCITY || '').trim();
		const name = String(row.CONAME || '').trim();

		if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null;
		if (!naicsCode || !province) return null;

		return {
			name,
			lat,
			lon,
			sales: Number.isFinite(sales) ? sales : 0,
			employees: Number.isFinite(employees) ? employees : 0,
			year: Number.isFinite(year) ? year : null,
			naicsCode,
			naicsDesc,
			province,
			city,
			color: '#999999'
		};
	}

	async function loadData() {
		isLoading = true;
		loadError = '';
		try {
			const response = await fetch((`${base}/data/map_export.csv`));
			if (!response.ok) {
				throw new Error('Failed to load map_export.csv');
			}
			const csv = await response.text();
			const rows = csvParse(csv);
			const parsed = rows.map(parseRow).filter(Boolean);

			const naicsMap = new Map();
			const provinces = new Set();
			const years = new Set();
			parsed.forEach((row) => {
				if (!naicsMap.has(row.naicsCode)) {
					naicsMap.set(row.naicsCode, row.naicsDesc || 'Unknown');
				}
				if (row.province) provinces.add(row.province);
				if (row.year) years.add(row.year);
			});

			naicsOptions = Array.from(naicsMap.entries())
				.map(([code, desc]) => ({ code, desc }))
				.sort((a, b) => a.code.localeCompare(b.code));

			naicsLabelByCode = Object.fromEntries(naicsOptions.map((option) => [option.code, option.desc]));

			provinceOptions = Array.from(provinces).sort();
			yearOptions = Array.from(years).sort((a, b) => a - b);
			
			// Initialize with Primary codes selected
			selectedNaics = naicsOptions
				.map((option) => option.code)
				.filter((code) => !secondaryNaicsCodes.includes(code));
				
			selectedProvinces = [...provinceOptions];
			selectedYear = yearOptions.includes(2025) ? 2025 : yearOptions[0] ?? allYearsLabel;

			const resolvedPalette = naicsPalette.map((token) => resolveCssColor(token));
			const resolvedOverrides = Object.fromEntries(
				Object.entries(naicsColorOverrides).map(([code, value]) => [code, resolveCssColor(value)])
			);

			colorByNaics = Object.fromEntries(
				naicsOptions.map((option, index) => [
					option.code,
					resolvedOverrides[option.code] ?? resolvedPalette[index % resolvedPalette.length]
				])
			);

			rawData = parsed.map((row) => ({
				...row,
				naicsDesc: naicsLabelByCode[row.naicsCode] || row.naicsDesc,
				color: colorByNaics[row.naicsCode] || '#999999'
			}));
		} catch (error) {
			console.error('Error loading defence map data:', error);
			loadError = 'Unable to load the defence sales data.';
		} finally {
			isLoading = false;
		}
	}

	function toggleAllNaics() {
		if (selectedNaics.length === naicsOptions.length) {
			selectedNaics = [];
			return;
		}
		selectedNaics = naicsOptions.map((option) => option.code);
	}

	function selectPrimary() {
		selectedNaics = naicsOptions
			.map((option) => option.code)
			.filter((code) => !secondaryNaicsCodes.includes(code));
	}

	function selectSecondary() {
		selectedNaics = naicsOptions
			.map((option) => option.code)
			.filter((code) => secondaryNaicsCodes.includes(code));
	}

	function toggleAllProvinces() {
		if (selectedProvinces.length === provinceOptions.length) {
			selectedProvinces = [];
			return;
		}
		selectedProvinces = [...provinceOptions];
	}

	function toggleNaics(code) {
		if (selectedNaics.includes(code)) {
			selectedNaics = selectedNaics.filter((item) => item !== code);
			return;
		}
		selectedNaics = [...selectedNaics, code];
	}

	function toggleProvince(province) {
		if (selectedProvinces.includes(province)) {
			selectedProvinces = selectedProvinces.filter((item) => item !== province);
			return;
		}
		selectedProvinces = [...selectedProvinces, province];
	}

	$: filteredData = rawData.filter(
		(row) =>
			selectedNaics.includes(row.naicsCode) &&
			selectedProvinces.includes(row.province) &&
			(selectedYear === allYearsLabel || row.year === selectedYear)
	);

	$: maxSales = filteredData.length ? Math.max(...filteredData.map((row) => row.sales)) : 1;

	const sizeLegend = [70, 140, 210];

	$: selectedSales = filteredData.map((row) => row.sales);
	$: totalSales = selectedSales.reduce((sum, value) => sum + value, 0);
	$: meanSales = mean(selectedSales);
	$: medianSales = median(selectedSales);
	$: firmCount = filteredData.length;
	$: selectedEmployees = filteredData.map((row) => row.employees)
	$: meanEmployees = mean(selectedEmployees)
	$: medianEmployees = median(selectedEmployees)

	$: naicsSummaries = (() => {
		const summaryMap = new Map();
		filteredData.forEach((row) => {
			if (!summaryMap.has(row.naicsCode)) {
				summaryMap.set(row.naicsCode, {
					naicsCode: row.naicsCode,
					naicsDesc: naicsLabelByCode[row.naicsCode] || row.naicsDesc,
					color: colorByNaics[row.naicsCode] || '#999999',
					sales: []
				});
			}
			summaryMap.get(row.naicsCode).sales.push(row.sales);
		});

		return Array.from(summaryMap.values())
			.map((entry) => ({
				...entry,
				total: entry.sales.reduce((sum, value) => sum + value, 0),
				mean: mean(entry.sales),
				median: median(entry.sales)
			}))
			.sort((a, b) => b.total - a.total);
	})();

	$: tableSourceData = rawData.filter((row) => selectedNaics.includes(row.naicsCode));
	$: tableYears = Array.from(
		new Set(rawData.map((row) => row.year).filter((year) => Number.isFinite(year)))
	).sort((a, b) => b - a);

	$: tableRows = naicsSummaries.map((entry) => {
		const totalsByYear = new Map();
		tableSourceData.forEach((row) => {
			if (row.naicsCode !== entry.naicsCode) return;
			const current = totalsByYear.get(row.year) ?? 0;
			totalsByYear.set(row.year, current + row.sales);
		});
		return {
			...entry,
			totalsByYear: tableYears.map((year) => totalsByYear.get(year) ?? 0)
		};
	});

	onMount(() => {
		loadData();
		
	});

	// console.log('NAICS options', naicsOptions)
	// const opticalinstru = naicsOptions.filter((option) =>
	// 	option.code === '333314'
	// );
	// console.log('opticalinstru', opticalinstru); // it's in diff years essentially.
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
			Defence spending in Canada has historically been difficult to gather. Canada has historically kept defence spending quite low.
			Recent commitments from the Federal Budget 2025 are to spend $30B in defence over 5 years and to reach 5% of gross domestic product (GDP) spending in defence by 2035.
			However, it isn't clear as to what the fiscal breakdown is like in what and who they will invest in.
			This tool aims to tackle historical defence spending based on company sales using the North American Industry Classification System (NAICS).
		</p>
		<p>
			This map plots defence-related NAICS industries across Canada and sizes points by total sales.
			Use the filters to focus on specific NAICS codes, provinces, or years. 
		</p>
	</div>

	{#if isLoading}
		<div class="status">Loading defence sales data...</div>
	{:else if loadError}
		<div class="status error">{loadError}</div>
	{:else}
		<div class="text" style="margin-bottom: 0px;">
			<h3>Filter the map</h3>
			<div class="filter-group">
				<span class="filter-label">NAICS codes</span>
				<div class="button-group">
					<button type="button" class="select-all" on:click={toggleAllNaics}>
						{selectedNaics.length === naicsOptions.length ? 'Clear all' : 'Select all'}
					</button>

					<button type="button" class="select-all" on:click={selectPrimary}>
						Select primary
					</button>

					<button type="button" class="select-all" on:click={selectSecondary}>
						Select secondary
					</button>
				</div>	
				<div class="button-group">
					{#each naicsOptions as option}
						<button
							type="button"
							class="filter-toggle-button {selectedNaics.includes(option.code) ? 'selected' : ''}"
							on:click={() => toggleNaics(option.code)}
						>
							<span class="filter-swatch" style="background-color: {colorByNaics[option.code]}"></span>
							<span class="filter-name">{option.desc}</span>
						</button>
					{/each}
				</div>
			</div>

			<div class="filter-group">
				<span class="filter-label">Provinces and territories</span>
				<button type="button" class="select-all" on:click={toggleAllProvinces}>
					{selectedProvinces.length === provinceOptions.length ? 'Clear all' : 'Select all'}
				</button>
				<div class="button-group">
					{#each provinceOptions as province}
						<button
							type="button"
							class="filter-toggle-button {selectedProvinces.includes(province) ? 'selected' : ''}"
							on:click={() => toggleProvince(province)}
						>
							<span class="filter-name">{province}</span>
						</button>
					{/each}
				</div>
			</div>

			<div class="filter-row">
				<div class="filter-group">
					<span class="filter-label">Year</span>
					<select class="year-select" bind:value={selectedYear}>
						<option value={allYearsLabel}>{allYearsLabel}</option>
						{#each yearOptions as year}
							<option value={year}>{year}</option>
						{/each}
					</select>
				</div>

				<div class="filter-group">
					<span class="filter-label">Circle size</span>
					<div class="size-legend">
						{#each sizeLegend as value}
							<div class="size-row">
								<span class="size-dot" style="--dot-size: {sizeToPixels(value)}px"></span>
								<span>{formatSales(value)}</span>
							</div>
						{/each}
					</div>
				</div>
			</div>
		</div>

		<section class="map-block">
			<DefenceMap data={filteredData} maxSales={maxSales} />
		</section>

		<div class="text">
			<h3>Selected summary</h3>
			<p>
				Firms: <strong>{firmCount}</strong> ·
				Mean employees: <strong>{formatEmployees(meanEmployees)}</strong> ·
				Median employees: <strong>{formatEmployees(medianEmployees)}</strong>
				<br>
				Total sales: <strong>{formatSales(totalSales)}</strong> · Mean sales:
				<strong>{formatSales(meanSales)}</strong> · Median sales:
				<strong>{formatSales(medianSales)}</strong>
			</p>
			<div class="naics-summary-list">
				{#each naicsSummaries as entry}
					<div class="naics-summary-row">
						<span class="filter-swatch" style="background-color: {entry.color}"></span>
						<div class="naics-summary-content">
							<div class="naics-summary-name">{entry.naicsDesc}</div>
							<div class="naics-summary-details">
								<span>Total: {formatSales(entry.total)}</span>
								<span>Mean: {formatSales(entry.mean)}</span>
								<span>Median: {formatSales(entry.median)}</span>
							</div>
						</div>
					</div>
				{/each}
			</div>
		</div>

		<div class="text chart-block">
			<h3>Selected NAICS sales by year</h3>
			<div class="table-wrap">
				<table class="naics-table">
					<thead>
						<tr>
							<th>NAICS</th>
							{#each tableYears as year}
								<th>{year}</th>
							{/each}
							<th>Total</th>
						</tr>
					</thead>
					<tbody>
						{#each tableRows as row}
							<tr>
								<td class="naics-cell">{row.naicsDesc}</td>
								{#each row.totalsByYear as value}
									<td>{formatSales(value)}</td>
								{/each}
								<td>{formatSales(row.total)}</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		</div>
	{/if}

	<div class="text  style=margin-bottom: 0px;">
		<h3>Data sources and methods</h3>
		<p>
			The company sales volume data is from the <a href="https://mdl.library.utoronto.ca/technology/tutorials/working-data-axle-historical-business-location-data">University of Toronto Library Data Axle</a>.
			In order to identify the companies we wanted to observe from the historical business dataset, we gathered a list of NAICS codes deemed to be at least partially defence related.
		</p>
		<p>
			"Primary defence" is deemed as NAICS codes where the companies' sales are their primarily defence-related. 
			"Secondary defence" is when defence is not the primary product that these companies produce. 
			For example, engineering services fall under many different sectors, but companies like <a href="https://www.wsp.com/en-me/sectors/defense">Williams Sale Partnership (WSP)</a> span dozens of different sectors, one of them being defence.
		</p>

		<p>You can download the data <a href="{base}/data/map_export.csv">here</a>.</p>
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

	.select-all {
		align-self: flex-start;
		background: transparent;
		border: 1px solid var(--brandGray);
		border-radius: 5px;
		padding: 4px 10px;
		font-family: OpenSans;
		font-size: 12px;
		color: var(--brandGray90);
		cursor: pointer;
	}

	.select-all:hover {
		border-color: var(--brandMedBlue);
		color: var(--brandMedBlue);
	}

	.button-group {
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
		margin-top: 2px;
	}

	.filter-toggle-button {
		display: inline-flex;
		align-items: center;
		gap: 8px;
		padding: 4px 8px;
		border: 1px solid var(--brandGray);
		border-radius: 5px;
		cursor: pointer;
		background-color: transparent;
		color: var(--brandGray90);
		user-select: none;
		font-family: OpenSans;
		font-size: 12px;
		font-weight: normal;
		opacity: 0.6;
		transition: opacity 0.2s ease, border 0.2s ease;
	}

	.filter-toggle-button.selected {
		opacity: 1;
		border-color: var(--brandLightBlue);
	}

	.filter-toggle-button:hover {
		opacity: 1;
		border-color: var(--brandMedBlue);
	}

	.filter-swatch {
		height: 12px;
		width: 4px;
		border-radius: 0px;
		flex: 0 0 auto;
	}

	.filter-name {
		line-height: 1.2;
	}

	.year-select {
		max-width: 220px;
		padding: 6px 10px;
		border: 1px solid var(--brandGray);
		border-radius: 5px;
		background: var(--brandWhite);
		color: var(--brandGray90);
		font-family: OpenSans;
		font-size: 13px;
	}

	.size-legend {
		display: flex;
		flex-wrap: wrap;
		gap: 16px;
		align-items: center;
	}

	.size-row {
		display: inline-flex;
		align-items: center;
		gap: 10px;
		font-size: 14px;
		font-family: OpenSans;
	}

	.size-dot {
		width: var(--dot-size);
		height: var(--dot-size);
		background: var(--brandGray90);
		border-radius: 50%;
		display: inline-block;
	}

	.map-block {
		width: 100%;
	}

	.summary-block {
		max-width: 100%;
	}

	.chart-block {
		margin-top: 24px;
	}

	.table-wrap {
		margin-top: 8px;
		width: 100%;
		overflow-x: auto;
		border: 1px solid var(--brandGray);
		background: var(--brandWhite);
	}

	.naics-table {
		width: 100%;
		border-collapse: collapse;
		font-family: OpenSans;
		font-size: 14px;
		min-width: 520px;
	}

	.naics-table th,
	.naics-table td {
		padding: 8px 10px;
		border-bottom: 1px solid var(--brandGray);
		text-align: right;
		white-space: nowrap;
	}

	.naics-table th {
		font-family: OpenSansBold;
		/* color: var(--brandGray90); */
		/* background: #f6f6f6; */
	}

	.naics-table td.naics-cell,
	.naics-table th:first-child {
		text-align: left;
		min-width: 240px;
	}

	.naics-table tbody tr:last-child td {
		border-bottom: none;
	}

	.summary-block p {
		margin-top: 8px;
		margin-bottom: 14px;
	}

	.naics-summary-list {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}

	.naics-summary-row {
		display: flex;
		gap: 12px;
		align-items: flex-start;
		font-family: OpenSans;
		font-size: 13px;
		color: var(--brandGray90);
	}

	.naics-summary-content {
		display: flex;
		flex-direction: column;
		gap: 4px;
		min-width: 0;
	}

	.naics-summary-name {
		font-family: OpenSansBold;
	}

	.naics-summary-details {
		display: flex;
		flex-wrap: wrap;
		gap: 15px;
		font-family: OpenSans;
		font-size: 12px;
		color: var(--brandGray70);
	}

	@media (max-width: 720px) {
		.page {
			padding: 32px 16px 64px;
		}

		.button-group {
			gap: 8px;
		}
	}
</style>