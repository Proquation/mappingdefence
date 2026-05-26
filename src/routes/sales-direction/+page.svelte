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

    let isLoading = true;
    let loadError = '';

    let b1Data = [];
    let b4Data = [];

    const years = [2016, 2018, 2020, 2022, 2024];
    let selectedYear = 2024;
    let viewMode = 'raw'; // 'raw' or 'percent'

    let chartEls = {};

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

    async function loadData() {
        try {
            const [resLoc, resGoods] = await Promise.all([
                fetch(`${base}/data/B1B2B3.csv`),
                fetch(`${base}/data/B4renamed_normalized.csv`)
            ]);

            if (!resLoc.ok || !resGoods.ok) throw new Error('Failed to load dataset(s)');

            const csvLoc = await resLoc.text();
            const csvGoods = await resGoods.text();

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
        .filter((d) => d.year === selectedYear)
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

            const activeValues = viewMode === 'percent' ? percentValues : rawValues;
            const brandBlue = resolveCssColor('--brandMedBlue') || '#007FA3';
			const brandDarkBlue = resolveCssColor('--brandDarkBlue') || '#005b75';

            const hovertemplate = viewMode === 'percent' 
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
                        ticksuffix: viewMode === 'percent' ? '%' : ''
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
    }

    onMount(() => {
        loadData();
    });

    $: {
        const _mode = viewMode;
        const _data = b4ByYear;
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
        <!-- TOP CONTROLS & TOTAL EXPENDITURE -->
        <div class="text">
            <div class="dashboard-controls">
                <div class="metric-card">
                    <h4>Total Sales ({selectedYear})</h4>
                    <div class="metric-val">{formatCurrency(locTotal)}</div>
                </div>
                <div class="control-actions">
                    <div class="filter-group">
                        <span class="filter-label">Display format</span>
                        <div class="button-group">
                            <button class="filter-toggle-button {viewMode === 'raw' ? 'selected' : ''}" on:click={() => (viewMode = 'raw')}>
                                Show Raw
                            </button>
                            <button class="filter-toggle-button {viewMode === 'percent' ? 'selected' : ''}" on:click={() => (viewMode = 'percent')}>
                                Show Percent
                            </button>
                        </div>
                    </div>
                    <div class="filter-group">
                        <span class="filter-label">Select Year (tabular views)</span>
                        <select class="year-select" bind:value={selectedYear}>
                            {#each years as y}
                                <option value={y}>{y}</option>
                            {/each}
                        </select>
                    </div>
                </div>
            </div>
        </div>

        <!-- SPIDER DIAGRAMS: GOODS & SERVICES -->
        <div class="text">
            <h3>Share of sales by goods and services</h3>
            <p>Spider diagrams comparing sectoral composition across all survey years.</p>
        </div>

        <div class="spider-scroll-wrapper">
            {#each years as y}
                <div class="spider-chart" bind:this={chartEls[y]}></div>
            {/each}
        </div>

        <!-- TABULAR LIST: LOCATIONS -->
        <div class="text">
            <h3>Share of sales by location</h3>
            <p>Tabular view showing sales breakdown for <strong>{selectedYear}</strong>, ordered by decreasing value.</p>
            <div class="table-wrap">
                <table class="data-table">
                    <thead>
                        <tr>
                            <th class="align-left">Location Breakdown</th>
                            <th>{viewMode === 'raw' ? 'Amount (Sales)' : 'Share of Total (%)'}</th>
                        </tr>
                    </thead>
                    <tbody>
                        {#each locFiltered as item}
                            <tr>
                                <td class="align-left cell-category">{item.category}</td>
                                <td>{formatValue(item.amount, locTotal, viewMode)}</td>
                            </tr>
                        {/each}
                    </tbody>
                </table>
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
        /* width: 100%; */
        display: flex;
        justify-content: space-between;
        /* align-items: center; */
        /* flex-wrap: wrap; */
        background: #fcfcfc;
        border: 1px solid var(--brandGray);
        padding: 20px 24px;
        border-radius: 8px;
        /* margin-bottom: 12px; */
        gap: 24px;
    }

    .metric-card h4 { margin: 0 0 8px; color: var(--brandGray70); font-size: 14px; }
    .metric-card .metric-val { font-size: 36px; font-family: TradeGothicBold; color: var(--brandDarkBlue); }

    .control-actions {
        display: flex;
        gap: 32px;
        flex-wrap: wrap;
    }

    .filter-group { display: flex; flex-direction: column; gap: 8px; }
    .filter-label { font-family: OpenSansBold; font-size: 13px; color: var(--brandGray90); }

    .button-group { display: flex; gap: 8px; }
    .filter-toggle-button {
        padding: 6px 12px;
        border: 1px solid var(--brandGray);
        border-radius: 5px;
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
        border-radius: 5px;
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
    }
    .spider-chart {
        flex: 0 0 480px; 
        height: 480px;
        border: 1px solid var(--brandGray);
        background-color: #fafafa;
        border-radius: 8px;
    }

    /* Simple Shared Table */
    .table-wrap {
        width: 100%;
        margin: 0 auto;
        overflow-x: auto;
        border: 1px solid var(--brandGray);
        border-radius: 8px;
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
        padding: 12px 16px;
        border-bottom: 1px solid var(--brandGray);
        text-align: right;
    }

    .data-table th { background: #f6f6f6; font-family: OpenSansBold; }
    .align-left { text-align: left !important; }
    .cell-category { min-width: 300px; color: var(--brandDarkBlue); font-family: OpenSansBold; }
    .data-table tbody tr:last-child td { border-bottom: none; }

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
	}
</style>