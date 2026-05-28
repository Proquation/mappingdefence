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
    import SizeWaffle from '$lib/SizeWaffle.svelte';

    let isLoading = true;
    let loadError = '';

    let b1Data = [];
    let b4Data = [];
    let sizeData = [];
    let usToCanData = [];
    let canToUsData = [];

    const years = [2016, 2018, 2020, 2022, 2024];
    const regions = ['all', 'canada', 'us', 'notcanada'];
    const regionLabels = {
        all: 'All regions',
        canada: 'Canada',
        us: 'United States',
        notcanada: 'Outside Canada'
    };
    let locYear = 2024;
    let selectedRegion = 'all';
    let locViewMode = 'raw'; // 'raw' or 'percent'
    let spiderViewMode = 'percent'; // 'raw' or 'percent'
    let waffleYear = 2024;
    let waffleMetric = 'amount';

    let chartEls = {};
    let sipriChartEl;

    const sizeMetricOptions = [
        { id: 'amount', label: 'Amount (Sales)', type: 'amount' },
        { id: 'percSales', label: 'Percent of total sales', type: 'percent' },
        { id: 'percExports', label: 'Percent of total exports', type: 'percent' },
        { id: 'percEmployment', label: 'Percent of total employment', type: 'percent' },
        { id: 'percRandD', label: 'Percent of total R&D', type: 'percent' }
    ];

    const sizeCategoryOrder = [
        'Enterprises with less than 100 employees',
        'Enterprises with between 100 and 249 employees',
        'Enterprises with between 250 and 499 employees',
        'Enterprises with 500 or more employees'
    ];

    const sizeCategoryColors = {
        'Enterprises with less than 100 employees': '--brandMedBlue',
        'Enterprises with between 100 and 249 employees': '--brandLightBlue',
        'Enterprises with between 250 and 499 employees': '--brandMedGreen',
        'Enterprises with 500 or more employees': '--brandDarkBlue'
    };

function formatCurrency(val) {
		if (val >= 1e9) return `$${(val / 1e9).toFixed(2)}B`;
		if (val >= 1e6) return `$${(val / 1e6).toFixed(1)}M`;
		return `$${val.toLocaleString()}`;
	}

	// Helper to format values (either $ Millions/Billions or Percentages)
	function formatValue(val, total, currentMode) {
		if (currentMode === 'percent') {
			if (!total) return '0.0%';
			return ((val / total) * 100).toFixed(1) + '%';
		} else {
			return formatCurrency(val);
		}
	}

	function resolveCssColor(token) {
		if (typeof document === 'undefined') return token;
		if (token?.startsWith('--')) {
			const value = getComputedStyle(document.documentElement).getPropertyValue(token).trim();
			return value || '#999999';
		}
		return token;
    }

    // Clean numbers formatted with quotes and commas
    function parseNum(str) {
        if (!str) return 0;
        return Number(String(str).replace(/,/g, '').trim()) || 0;
    }

    function parseNumOrNull(str) {
        if (!str || String(str).trim() === 'NA') return null;
        const num = Number(String(str).replace(/,/g, '').trim());
        return isNaN(num) ? null : num;
    }

    function normalizeLabel(value) {
        return String(value ?? '').replace(/\s+/g, ' ').trim();
    }

    function resolveRegion(category) {
        const text = normalizeLabel(category).toLowerCase();
        if (text.includes('united states') || text.includes('u.s.')) return 'us';
        if (text.includes('canadian') || text.startsWith('domestic')) return 'canada';
        if (text.includes('breakdown not specified for any category')) return 'unknown';
        if (text.includes('other countries')) return 'notcanada';
        return 'notcanada';
    }

    function getRowValue(row, label) {
        const match = Object.keys(row).find((key) => key.trim() === label.trim());
        return match ? row[match] : '';
    }

    async function loadData() {
        try {
            const [resLoc, resGoods, resSize, resUsToCan, resCanToUs] = await Promise.all([
                fetch(`${base}/data/B1B2B3.csv`),
                fetch(`${base}/data/B4renamed_normalized.csv`),
                fetch(`${base}/data/SIZE.csv`),
                fetch(`${base}/data/fixed_ustocanexports.csv`),
                fetch(`${base}/data/fixed_cantousexports.csv`)
            ]);

            if (!resLoc.ok || !resGoods.ok || !resSize.ok || !resUsToCan.ok || !resCanToUs.ok) throw new Error('Failed to load dataset(s)');

            const csvLoc = await resLoc.text();
            const csvGoods = await resGoods.text();
            const csvSize = await resSize.text();
            const csvUsToCan = await resUsToCan.text();
            const csvCanToUs = await resCanToUs.text();

            b1Data = csvParse(csvLoc).map((row) => ({
                category: row['Type of Sale'].trim(),
                amount: parseNum(row['Amount']),
                year: Number(row['Year'])
            })).filter((d) => d.year && d.amount > 0);

            b4Data = csvParse(csvGoods).map((row) => ({
                category: row['Goods and Services'].trim(),
                amount: parseNum(row['Sales of Goods and Services']),
                year: Number(row['Year'])
            })).filter((d) => d.year && d.amount > 0);

            sizeData = csvParse(csvSize).map((row) => ({
                size: normalizeLabel(row['Size']),
                amount: parseNum(row['Amount']),
                year: Number(row['Year']),
                percSales: parseNum(getRowValue(row, "Enterprises' % of total Defence industry sales")),
                percExports: parseNum(getRowValue(row, "Enterprises' % of total Defence industry exports")),
                percEmployment: parseNum(getRowValue(row, "Enterprises' % of total Defence industry employment")),
                percRandD: parseNum(getRowValue(row, "Enterprises' % of total Defence industry R&D"))
            })).filter((d) => d.year && d.amount > 0);

            usToCanData = csvParse(csvUsToCan).map((row) => ({
                year: Number(row['Year']),
                value: parseNumOrNull(row['Canada'])
            }));

            canToUsData = csvParse(csvCanToUs).map((row) => ({
                year: Number(row['Year']),
                value: parseNumOrNull(row['United_States'])
            }));

        } catch (error) {
            console.error('Error loading survey data:', error);
            loadError = 'Unable to load sales data.';
        } finally {
            isLoading = false;
        }
    }

    // ---------------------------
    // Location Table Data (B1B2B3)
    // ---------------------------
    $: locFiltered = b1Data
        .filter((d) => d.year === locYear)
        .filter((d) => {
            if (selectedRegion === 'all') return true;
            const region = resolveRegion(d.category);
            if (selectedRegion === 'notcanada') return region === 'notcanada';
            return region === selectedRegion;
        })
        .sort((a, b) => b.amount - a.amount);
    
    $: locTotal = locFiltered.reduce((sum, d) => sum + d.amount, 0);

    // ---------------------------
    // Goods/Services Spider Data (B4)
    // ---------------------------
    $: b4ByYear = years.map((y) => {
        let items = b4Data.filter((d) => d.year === y);
        let total = items.reduce((sum, d) => sum + d.amount, 0);
        return { year: y, items, total };
    });

    // ---------------------------
    // Company Size Data (SIZE)
    // ---------------------------
    $: sizeYearItems = sizeData.filter((d) => d.year === waffleYear); // for specific year
    // defaults to first option if not selected
    $: waffleMetricDef = sizeMetricOptions.find((metric) => metric.id === waffleMetric) || sizeMetricOptions[0];
    // total value for chart -> summ of all amounts for selected year, if percentage, then using 100 as total
    $: waffleTotal = waffleMetricDef.type === 'amount'
        ? sizeYearItems.reduce((sum, d) => sum + d.amount, 0)
        : 100;
    $: waffleItems = sizeCategoryOrder.map((label) => {
        const match = sizeYearItems.find((d) => d.size === label);
        const value = match ? match[waffleMetricDef.id] ?? 0 : 0;
        const displayValue = waffleMetricDef.type === 'amount'
            ? `${value.toLocaleString()}`
            : `${value.toFixed(1)}%`;
        return {
            label,
            value,
            displayValue,
            color: sizeCategoryColors[label] || '--brandGray'
        };
    });



    let Plotly;
    async function ensurePlotly() {
        if (Plotly) return Plotly;
        const module = await import('plotly.js-dist-min');
        Plotly = module.default ?? module;
        return Plotly;
    }

    async function renderCharts() {
        await ensurePlotly();

        b4ByYear.forEach(({ year, items, total }) => {
            const el = chartEls[year];
            if (!el || items.length === 0) return;

            // Truncate long labels for a cleaner radar chart
            const labels = items.map((d) => d.category.length > 25 ? d.category.slice(0, 25) + '...' : d.category);
            const rawValues = items.map((d) => d.amount);
            const percentValues = rawValues.map((v) => (v / total) * 100);
            const fullLabels = items.map((d) => d.category); // full labels for tooltips

            // Append first element to the end to close the spider web shape
            labels.push(labels[0]);
            rawValues.push(rawValues[0]);
            percentValues.push(percentValues[0]);
            fullLabels.push(fullLabels[0]); // Also duplicate for the closing point

            const activeValues = spiderViewMode === 'percent' ? percentValues : rawValues;
            const brandBlue = resolveCssColor('--brandMedBlue') || '#007FA3';
			const brandDarkBlue = resolveCssColor('--brandDarkBlue') || '#005b75';

            const hovertemplate = spiderViewMode === 'percent' 
            ? '<b>%{text}</b><br>Percentage: %{r:.1f}%<br>Year: ' + year + '<extra></extra>'
            : '<b>%{text}</b><br>Sales: %{r:$,.0f}<br>Year: ' + year + '<extra></extra>';


			const data = [
				{
					type: 'scatterpolar',
					r: activeValues,
					theta: labels,
					fill: 'toself',
                    mode: 'lines+markers', // applies to all years for some reason...
					name: String(year),
					marker: { color: brandBlue, size: 8, symbol: 'circle' },
					line: { color: brandBlue },
                    hoverinfo: 'text',
                    hovertemplate: hovertemplate,
                    text: fullLabels,
                    hoverlabel: {
                        bgcolor: 'white',
                        bordercolor: brandBlue,
                        font: { family: 'OpenSans', size: 12 },
                        namelength: -1  
                    }
                }
            ];

            
            const layout = {
                polar: {
                    radialaxis: {
                        visible: true,
                        ticksuffix: spiderViewMode === 'percent' ? '%' : ''
                    },
                    angularaxis: {
                        tickfont: { size: 10, family: 'OpenSans' }
                    }
                },
                title: {
                    text: `${year}`,
                    font: { family: 'TradeGothicBold', size: 18, color: brandDarkBlue }
                },
                showlegend: false,
                margin: { l: 80, r: 80, t: 40, b: 60 },  // Increased bottom margin for labels
                width: 680,
                height: 480,
                paper_bgcolor: 'rgba(0,0,0,0)',
                plot_bgcolor: 'rgba(0,0,0,0)',
                hovermode: 'closest'
            };

            const config = { displayModeBar: false, responsive: false, staticPlot: false};
            Plotly.react(el, data, layout, config);
        });

        if (sipriChartEl && usToCanData.length > 0 && canToUsData.length > 0) {
            const brandBlue = resolveCssColor('--brandMedBlue') || '#007FA3';
            const brandDarkBlue = resolveCssColor('--brandDarkBlue') || '#005b75';

            const trace1 = {
                x: usToCanData.map(d => d.year),
                y: usToCanData.map(d => d.value),
                mode: 'lines+markers',
                name: 'US Exports to Canada',
                line: { color: brandDarkBlue, width: 2 },
                marker: { color: brandDarkBlue, size: 6 },
                connectgaps: true
            };

            const trace2 = {
                x: canToUsData.map(d => d.year),
                y: canToUsData.map(d => d.value),
                mode: 'lines+markers',
                name: 'Canada Exports to US',
                line: { color: brandBlue, width: 2 },
                marker: { color: brandBlue, size: 6 },
                connectgaps: true
            };

            const sipriLayout = {
                font: { family: 'OpenSans' },
                xaxis: { title: "Year", showgrid: false },
                yaxis: { title: "TIV (Trend Indicator Values)" },
                hovermode: 'x unified',
                margin: { l: 60, r: 20, t: 20, b: 40 },
                showlegend: true,
                legend: { x: 0, y: 1.1, orientation: 'h' }
            };

            Plotly.react(sipriChartEl, [trace1, trace2], sipriLayout, { displayModeBar: false, responsive: true });
        }
    }

    onMount(() => {
        loadData();
    });

    $: {
        const _mode = spiderViewMode;
        const _data = b4ByYear;
        const _us = usToCanData;
        const _can = canToUsData;
        if (!isLoading) {
            // Small timeout ensures DOM targets exist before plotting
            setTimeout(renderCharts, 50);
        }
    }
</script>

<Password />

<Logo logoType="Blue" backgroundColor="var(--brandWhite)" />

<main class="page">
    <TitleStandard title="Where are defence sales going?" />
    <div class="text">
        <AuthorDate
			authors="<a href='https://schoolofcities.utoronto.ca/people/karen-chapple/' target='_blank'>Karen Chapple</a>, <a href='https://discover.research.utoronto.ca/8035-tara-vinodrai' target='_blank'>Tara Vinodrai</a>, <a href='https://www.linkedin.com/in/yihoi-jung-0b95351b5/' target='_blank'>Yihoi Jung</a>, Sarah Gibbons, Andrew Feng"
            date="May 2026."
        />
        <p>
            Data comes from the Canadian Defence, Aerospace and Commercial and Civil Marine Sectors Survey (CDACCMS).
            This page visualizes the composition of goods and services alongside the geographical breakdown of defence buyers over time.
        </p>
    </div>

    {#if isLoading}
        <div class="status">Loading survey data...</div>
    {:else if loadError}
        <div class="status error">{loadError}</div>
    {:else}
        

        <!-- SPIDER DIAGRAMS: GOODS & SERVICES -->
        <div class="text">
            <h3>Sales by goods and services</h3>
            <p>Spider diagrams comparing sectoral composition across all survey years.</p>
            <div class="filter-group inline-filters">
                <span class="filter-label">Spider chart metric</span>
                <div class="button-group">
                    <button class="filter-toggle-button {spiderViewMode === 'raw' ? 'selected' : ''}" on:click={() => (spiderViewMode = 'raw')}>
                        Show Raw
                    </button>
                    <button class="filter-toggle-button {spiderViewMode === 'percent' ? 'selected' : ''}" on:click={() => (spiderViewMode = 'percent')}>
                        Show Percent
                    </button>
                </div>
            </div>
        </div>

        <div class="spider-scroll-wrapper">
            {#each [...years].reverse() as y}
                <div class="spider-chart" bind:this={chartEls[y]}></div>
            {/each}
        </div>

        <!-- TOP CONTROLS & TOTAL EXPENDITURE -->
        <div class="text">
            <div class="dashboard-controls">
                <div class="control-actions">
                    <div class="metric-group">
                        <div class="metric-card">
                            <h4>Total Sales ({locYear})</h4>
                            <div class="metric-val">{formatCurrency(locTotal)}</div>
                        </div>
                    </div>
                    <div class="filter-group">
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
                    <div class="bottom-filters">
                        <div class="filter-group">
                            <span class="filter-label">Region</span>
                            <select class="year-select" bind:value={selectedRegion}>
                                {#each regions as r}
                                    <option value={r}>{regionLabels[r]}</option>
                                {/each}
                            </select>
                        </div>
                        <div class="filter-group">
                            <span class="filter-label">Location year</span>
                            <select class="year-select" bind:value={locYear}>
                                {#each years as y}
                                    <option value={y}>{y}</option>
                                {/each}
                            </select>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <div class="text">
            <h3>Historical Arms Transfers (1950 - 2025)</h3>
            <p>
                Time series of arms exports between the United States and Canada. Data is sourced from the 
                <a href="https://www.sipri.org/databases/armstransfers" target="_blank">SIPRI Arms Transfers Database</a>.
                Missing data points are left blank.
            </p>
            <div class="table-wrap" style="padding: 20px;">
                <div bind:this={sipriChartEl} style="width: 100%; height: 400px;"></div>
            </div>
        </div>

        <!-- TABULAR LIST: LOCATIONS -->
        <div class="text">
            <h3>Sales by location</h3>
            <p>Tabular view showing sales breakdown for <strong>{locYear}</strong>, ordered by decreasing value.</p>
            <div class="table-wrap">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th class="align-left">Location Breakdown</th>
                            <th>{locViewMode === 'raw' ? 'Amount (Sales)' : 'Share of Total (%)'}</th>
                        </tr>
                    </thead>
                    <tbody>
                        {#each locFiltered as item}
                            <tr>
                                <td class="align-left cell-category">{item.category}</td>
                                <td>{formatValue(item.amount, locTotal, locViewMode)}</td>
                            </tr>
                        {/each}
                        <tr class="total-row">
                            <td class="align-left cell-category">Total</td>
                            <td>{formatValue(locTotal, locTotal, locViewMode)}</td>
                        </tr>
                    </tbody>
                </table>
            </div>
        </div>

        <div class="text">
            <h3>Share of sales by company size</h3>
            <p>Waffle chart showing the distribution of sales, exports, employment, and R&D by company size.</p>
            <div class="waffle-controls">
                <div class="filter-group">
                    <span class="filter-label">Year</span>
                    <select class="year-select" bind:value={waffleYear}>
                        {#each years as y}
                            <option value={y}>{y}</option>
                        {/each}
                    </select>
                </div>
                <div class="filter-group">
                    <span class="filter-label">Metric</span>
                    <select class="year-select" bind:value={waffleMetric}>
                        {#each sizeMetricOptions as metric}
                            <option value={metric.id}>{metric.label}</option>
                        {/each}
                    </select>
                </div>
            </div>
            <div class="waffle-layout">
                <SizeWaffle items={waffleItems} total={waffleTotal} />
                <div class="waffle-legend">
                    {#each waffleItems as item}
                        <div class="waffle-legend-row">
                            <span class="waffle-swatch" style="background-color: {resolveCssColor(item.color)}"></span>
                            <span class="waffle-label">{item.label}:</span>
                            <span class="waffle-value">
                                {waffleMetricDef.type === 'percent'
                                    ? `${item.value.toFixed(1)}%`
                                    : `${item.value}`}
                            </span>
                        </div>
                    {/each}
                </div>
            </div>
        </div>
    {/if}
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
        padding: 60px 20px;
        color: var(--brandGray90);
        font-family: OpenSans;
    }
    .status.error { color: var(--brandRed); }

    .section-container {
        width: 100%;
        border-top: 2px solid var(--brandDarkBlue);
        padding-top: 24px;
    }

    /* Controls & Top Bar */
    .dashboard-controls {
        background: #fcfcfc;
        border: 1px solid var(--brandGray);
        padding: 20px 24px;
        border-radius: 3px;
        width: 100%;
    }

    .metric-card h4 { margin: 0 0 8px; color: var(--brandGray70); font-size: 14px; }
    .metric-card .metric-val { font-size: 36px; font-family: TradeGothicBold; color: var(--brandDarkBlue); }

    .control-actions {
        display: grid;
        grid-template-columns: repeat(2, 1fr);
        gap: 24px 32px;
        width: 100%;
    }

    .metric-group {
        display: flex;
        flex-direction: column;
        justify-content: flex-end;
    }

    .filter-group { display: flex; flex-direction: column; gap: 8px; }

    .bottom-filters {
        display: contents;
    }
    .filter-label { font-family: OpenSansBold; font-size: 13px; color: var(--brandGray90); }

    .button-group { display: flex; gap: 8px; }
    .filter-toggle-button {
        padding: 6px 12px;
        border: 1px solid var(--brandGray);
        border-radius: 3px;
        cursor: pointer;
        background-color: var(--brandWhite);
        color: var(--brandGray90);
        font-family: OpenSans;
        font-size: 13px;
    }
    .filter-toggle-button.selected {
        background-color: var(--brandMedBlue);
        color: white;
        border-color: var(--brandDarkBlue);
    }

    .year-select {
        padding: 8px 12px;
        border: 1px solid var(--brandGray);
        border-radius: 3px;
        font-family: OpenSans;
        font-size: 14px;
        min-width: 120px;
    }

    /* Spider Charts Scroll View */
    .spider-scroll-wrapper {
        display: flex;
        overflow-x: auto;
        gap: 24px;
        padding-bottom: 16px;
        border-left: 1px solid var(--brandGray); 
        border-right: 1px solid var(--brandGray); 
    }
    .spider-chart {
        flex: 0 0 480px; 
        height: 480px;
        border: 1px solid var(--brandGray);
        background-color: #fafafa;
        border-radius: 3px;
    }

    /* Simple Shared Table */
    .table-wrap {
        width: 100%;
        margin: 0 auto;
        overflow-x: auto;
        border: 1px solid var(--brandGray);
        border-radius: 3px;
        background: var(--brandWhite);
    }

    .data-table {
        width: 100%;
        margin: 0 auto;
        border-collapse: collapse;
        font-family: OpenSans;
        font-size: 14px;
    }

    .data-table th, .data-table td {
        padding: 6px 8px;
        border-bottom: 1px solid var(--brandGray);
        text-align: right;
    }

    .data-table th:first-child,
    .data-table td:first-child {
        border-right: 1px solid var(--brandGray);
    }

    .data-table th { background: #f6f6f6; font-family: OpenSansBold}
    .align-left { text-align: left !important; }
    .cell-category { min-width: 300px;  font-family: OpenSans; }
    .data-table tbody tr:last-child td { border-bottom: none; }

    .total-row {
        font-family: OpenSansBold;
    }

    .inline-filters {
        margin-top: 12px;
    }

    .waffle-controls {
        display: flex;
        flex-wrap: wrap;
        gap: 16px 24px;
        margin-top: 12px;
    }

    .waffle-layout {
        display: grid;
        grid-template-columns: minmax(220px, 360px) minmax(240px, 1fr);
        gap: 24px;
        align-items: start;
        margin-top: 16px;
    }

    .waffle-legend {
        display: flex;
        flex-direction: column;
        gap: 10px;
        font-family: OpenSans;
        font-size: 14px;
        color: var(--brandGray90);
    }

    .waffle-legend-row {
        display: grid;
        grid-template-columns: 16px 1fr auto;
        gap: 10px;
        align-items: center;
    }

    .waffle-swatch {
        width: 14px;
        height: 14px;
        border-radius: 3px;
        border: 1px solid var(--brandGray);
    }

    .waffle-label {
        font-family: OpenSans;
    }

    .waffle-value {
        font-family: OpenSansBold;
    }

    .summary-block {
		max-width: 100%;
	}

    @media (max-width: 720px) {
		.page {
			padding: 32px 16px 64px;
		}

		.button-group {
			gap: 8px;
		}

        .waffle-layout {
            grid-template-columns: 1fr;
        }
	}
</style>