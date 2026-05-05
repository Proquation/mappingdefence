

<script>
	import { onMount } from 'svelte';
	import { csvParse } from 'd3-dsv';

	import '$lib/assets/global-styles.css';
	import Logo from '$lib/LogoTop.svelte';
	import Footer from '$lib/Footer.svelte';
	import AuthorDate from '$lib/AuthorDate.svelte';
	import TitleStandard from '$lib/TitleStandard.svelte';
	import DefenceMap from '$lib/DefenceMap.svelte';
	import Password from '$lib/Password.svelte';

	const naicsPalette = [
		'#2e7d6b',
		'#c07f2f',
		'#7a6da6',
		'#b66a8a',
		'#4f8a3b',
		'#b28b1c',
		'#8a5f2b',
		'#4c7f8f',
		'#7f9c6e',
		'#b7786d',
		'#a98a5a',
		'#8e7b9c'
	];

	const engineeringNaicsCode = '541330';
	const naicsColorOverrides = {
		'336411': '#2f5da7',
		'541330': '#c43d32'
	};

	let isLoading = true;
	let loadError = '';
	let rawData = [];
	let filteredData = [];
	let naicsOptions = [];
	let provinceOptions = [];
	let yearOptions = [];
	let selectedNaics = [];
	let selectedProvinces = [];
	const allYearsLabel = 'All years';
	let selectedYear = allYearsLabel;
	let colorByNaics = {};
	let maxSales = 1;
	let chartEl;
	const chartYears = Array.from({ length: 9 }, (_, index) => 2017 + index);

	const minRadius = 3;
	const maxRadius = 28;

	function formatSales(value) {
		if (!Number.isFinite(value)) return 'N/A';
		if (value >= 1000) return `${(value / 1000).toFixed(1)}B`;
		return `${value.toFixed(1)}M`;
	}

	function formatSalesLong(value) {
		if (!Number.isFinite(value)) return 'N/A';
		return `$${value.toFixed(2)}M`;
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
			const response = await fetch('/data/map_export.csv');
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

			provinceOptions = Array.from(provinces).sort();
			yearOptions = Array.from(years).sort((a, b) => a - b);
			selectedNaics = naicsOptions
				.map((option) => option.code)
				.filter((code) => code !== engineeringNaicsCode);
			selectedProvinces = [...provinceOptions];
			selectedYear = yearOptions.includes(2025) ? 2025 : yearOptions[0] ?? allYearsLabel;

			colorByNaics = Object.fromEntries(
				naicsOptions.map((option, index) => [
					option.code,
					naicsColorOverrides[option.code] ?? naicsPalette[index % naicsPalette.length]
				])
			);

			rawData = parsed.map((row) => ({
				...row,
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

	$: chartSourceData = rawData;

	function buildChartSeries() {
		const totals = new Map();
		chartSourceData.forEach((row) => {
			if (!totals.has(row.naicsCode)) {
				totals.set(row.naicsCode, {
					naicsCode: row.naicsCode,
					naicsDesc: row.naicsDesc,
					totalsByYear: new Map()
				});
			}
			const entry = totals.get(row.naicsCode);
			const current = entry.totalsByYear.get(row.year) ?? 0;
			entry.totalsByYear.set(row.year, current + row.sales);
		});

		return Array.from(totals.values())
			.map((entry) => ({
				name: `${entry.naicsDesc} - ${entry.naicsCode}`,
				x: chartYears,
				y: chartYears.map((year) => entry.totalsByYear.get(year) ?? 0),
				marker: { color: colorByNaics[entry.naicsCode] || '#999999' },
				type: 'bar'
			}))
			.sort((a, b) => b.y.reduce((sum, value) => sum + value, 0) - a.y.reduce((sum, value) => sum + value, 0));
	}

	let Plotly;

	async function ensurePlotly() {
		if (Plotly) return Plotly;
		const module = await import('plotly.js-dist-min');
		Plotly = module.default ?? module;
		return Plotly;
	}

	async function renderChart() {
		if (!chartEl) return;
		await ensurePlotly();
		const data = buildChartSeries();
		const layout = {
			barmode: 'stack',
			height: 400,
			width: 600,
			margin: { l: 0, r: 0, t: 0, b: 0 },
			hoverlabel: {
				namelength: -1,
				align: 'left',
				font: { family: 'OpenSans', size: 12 }
			},
			xaxis: {
				tickvals: chartYears,
				tickmode: 'array',
				ticktext: chartYears.map((year) => String(year)),
				title: ''
			},
			yaxis: {
				tickprefix: '$',
				ticksuffix: 'M',
				title: ''
			},
			legend: {
				orientation: 'h',
				y: -0.25,
				x: 0,
				font: { family: 'OpenSans', size: 11 }
			},
			font: { family: 'OpenSans' },
			paper_bgcolor: 'rgba(0,0,0,0)',
			plot_bgcolor: 'rgba(0,0,0,0)'
		};
		const config = { displayModeBar: false, responsive: true };
		Plotly.react(chartEl, data, layout, config);
	}

	$: naicsSummaries = (() => {
		const summaryMap = new Map();
		filteredData.forEach((row) => {
			if (!summaryMap.has(row.naicsCode)) {
				summaryMap.set(row.naicsCode, {
					naicsCode: row.naicsCode,
					naicsDesc: row.naicsDesc,
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

	onMount(() => {
		loadData();
	});

	$: if (chartEl && !isLoading) {
		renderChart();
	}
</script>

<Password />

<Logo logoType="Blue" backgroundColor="var(--brandWhite)" />

<main class="page">
	<TitleStandard title="Where is defence industry activity concentrated in Canada?" />
	<div class="text">
		<AuthorDate
			authors="<a href='https://schoolofcities.utoronto.ca/people/karen-chapple/' target='_blank'>Karen Chapple</a>, <a href='https://www.linkedin.com/in/yihoi-jung-0b95351b5/' target='_blank'>Yihoi Jung</a>, <a href='https://schoolofcities.utoronto.ca/people/jeff-allen/' target='_blank'>Jeff Allen</a>"
			date="May 2026."
		/>


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
				<button type="button" class="select-all" on:click={toggleAllNaics}>
					{selectedNaics.length === naicsOptions.length ? 'Clear all' : 'Select all'}
				</button>
				<div class="button-group">
					{#each naicsOptions as option}
						<button
							type="button"
							class="filter-toggle-button {selectedNaics.includes(option.code) ? 'selected' : ''}"
							on:click={() => toggleNaics(option.code)}
						>
							<span class="filter-swatch" style="background-color: {colorByNaics[option.code]}"></span>
							<span class="filter-name">{option.desc} - {option.code}</span>
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

		<div class="text summary-block">
			<h3>Selected summary</h3>
			<p>
				Total sales: <strong>{formatSalesLong(totalSales)}</strong> · Mean sales:
				<strong>{formatSalesLong(meanSales)}</strong> · Median sales:
				<strong>{formatSalesLong(medianSales)}</strong>
			</p>
			<div class="naics-summary-list">
				{#each naicsSummaries as entry}
					<div class="naics-summary-row">
						<span class="filter-swatch" style="background-color: {entry.color}"></span>
						<span class="naics-summary-name">{entry.naicsDesc} - {entry.naicsCode}</span>
						<span class="naics-summary-metric">Total: {formatSalesLong(entry.total)}</span>
						<span class="naics-summary-metric">Mean: {formatSalesLong(entry.mean)}</span>
						<span class="naics-summary-metric">Median: {formatSalesLong(entry.median)}</span>
					</div>
				{/each}
			</div>
		</div>

		<div class="text chart-block">
			<h3>NAICS sales by year</h3>
			<div class="chart-container" bind:this={chartEl}></div>
		</div>
	{/if}
</main>

<Footer />

<style>
	.page {
		max-width: 1400px;
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
		margin-bottom: 20px;
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
		gap: 10px;
		margin-top: 4px;
	}

	.filter-toggle-button {
		display: inline-flex;
		align-items: center;
		gap: 8px;
		padding: 6px 10px;
		border: 1px solid var(--brandGray);
		border-radius: 5px;
		cursor: pointer;
		background-color: transparent;
		color: var(--brandGray90);
		user-select: none;
		font-family: OpenSans;
		font-size: 13px;
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
		height: 15px;
		width: 5px;
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
		margin-top: 20px;
	}

	.chart-block {
		margin-top: 24px;
	}

	.chart-container {
		width: 100%;
		min-height: 360px;
	}

	.summary-block p {
		margin-top: 8px;
		margin-bottom: 14px;
	}

	.naics-summary-list {
		display: flex;
		flex-direction: column;
		gap: 10px;
	}

	.naics-summary-row {
		display: flex;
		flex-wrap: wrap;
		gap: 8px 16px;
		align-items: baseline;
		font-family: OpenSans;
		font-size: 13px;
		color: var(--brandGray90);
	}

	.naics-summary-name {
		font-family: OpenSansBold;
	}

	.naics-summary-metric {
		color: var(--brandGray70);
	}

	:global(.logo-container .menu-toggle) {
		display: none;
	}

	:global(.logo-container .dropdown) {
		display: none;
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