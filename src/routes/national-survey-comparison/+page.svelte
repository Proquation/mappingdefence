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
    let sizeData = [];
    let sankeyEl;

    let yearA = 2016;
    let yearB = 2024;
    $: selectedYears = [yearA, yearB].sort((a, b) => a - b ); // ascending - oldest first

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

    const sizeMetricOptions = [
        { id: 'amount', label: 'Number of firms', type: 'amount' },
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

    const sizeLabels = {
        'Enterprises with less than 100 employees':       '< 100 employees',
        'Enterprises with between 100 and 249 employees': '100–249 employees',
        'Enterprises with between 250 and 499 employees': '250–499 employees',
        'Enterprises with 500 or more employees':         '500+ employees',
    };

    const b4ShortLabels = {
        'Simulation Systems for Naval':              'Naval Simulation',
        'Simulation Systems for Aircraft':           'Air/Land Simulation',
        'Unmanned Aerial Systems':                   'UAS/Drones',
        'Military Aircraft Maintenance':             'Aircraft Maint.',
        'Aircraft Fabrication':                      'Aircraft Fabrication',
        'Combat Vehicles Maintenance':               'Combat Vehicle Maint.',
        'Combat Vehicles and Components':            'Combat Vehicles',
        'Naval Ship Maintenance':                    'Naval Ship Maint.',
        'Naval Vessel Construction':                 'Naval Construction',
        "Naval Ships' Structural":                   'Naval Structures',
        'Naval Ship-Borne Mission':                  'Naval Mission Systems',
        'Land-Based Communications':                 'Land Comms',
        'Airborne Communications':                   'Airborne Comms',
        'Land-Based Sensor':                         'Land Sensors',
        'Airborne Sensor':                           'Airborne Sensors',
        'Military Space Systems':                    'Space Systems',
        'Firearms, Ammunition':                      'Firearms & Ammo',
        'Firearms and Other Weapon':                 'Firearms & Weapons',
        'Ammunition, Missiles':                      'Ammo & Missiles',
        'Other Defence':                             'Other Defence',
        'Military Personal Protect':                 'Personal Protection',
        'Military Training':                         'Training Services',
        'Land-Based Mission System':                 'Land Mission Systems',
        'Naval Vessel Mission':                      'Naval Mission Systems',
        'Aircraft Mission Systems':                  'Aircraft Mission Systems',
    };

    function shortB4Label(full) {
        const key = Object.keys(b4ShortLabels).find(k => full.startsWith(k));
        return key ? b4ShortLabels[key] : full.slice(0, 18);
    }

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

    function normalizeCategory(cat) {
        const c = cat.trim();
        if (c.includes('non-government') && c.includes('Canadian'))
            return 'Sales to non-government entities in Canadian defence & aerospace sectors';
        if (c.includes('non-government') && (c.includes('U.S.') || c.includes('US')))
            return 'Sales to non-government entities in U.S. defence & aerospace sectors';
        if (c.startsWith('Sales to Central America'))
            return 'Sales to Central America, Caribbean, Mexico and South America';
        if (c === 'Sales to Asia and Oceania')
            return 'Sales to Asia and Oceania - Other than Australia & New Zealand';
        return c;
    }

    function hexToRgba(hex, alpha) {
        const h = hex.replace('#', '');
        const full = h.length === 3 ? h.split('').map((c) => c + c).join('') : h;
        const r = parseInt(full.slice(0, 2), 16);
        const g = parseInt(full.slice(2, 4), 16);
        const b = parseInt(full.slice(4, 6), 16);
        return `rgba(${r}, ${g}, ${b}, ${alpha})`;
    }

    async function renderSankey() {
        const d3 = await import('d3-selection');
        if (!sankeyEl) return;
        sankeyEl.innerHTML = '';
        sankeyEl.style.position = 'relative';   // anchor for the tooltip

        const metricDef = sizeMetricOptions.find((m) => m.id === waffleMetric) || sizeMetricOptions[0];
        const [yearLow, yearHigh] = [...selectedYears].sort((a, b) => a - b);
        const catColors = {
            'Enterprises with less than 100 employees':       '#6FC7EA',
            'Enterprises with between 100 and 249 employees': '#a8dff5',
            'Enterprises with between 250 and 499 employees': '#8DBF2E',
            'Enterprises with 500 or more employees':         '#ffffff',
        };

        const lowItems  = sizeData.filter((d) => d.year === yearLow);
        const highItems = sizeData.filter((d) => d.year === yearHigh);
        const lowTotal  = lowItems.reduce((s, d) => s + (d[metricDef.id] ?? 0), 0);
        const highTotal = highItems.reduce((s, d) => s + (d[metricDef.id] ?? 0), 0);

        const W = sankeyEl.clientWidth || 900, H = 420;
        const nodeW = 14, padBetween = 18, marginY = 10;
        const nCats = sizeCategoryOrder.length;
        const usableH = H - marginY * 2 - padBetween * (nCats - 1);

        const svg = d3.select(sankeyEl).append('svg')
            .attr('width', '100%').attr('height', H).attr('viewBox', `0 0 ${W} ${H}`);

        // floating tooltip div
        const tip = d3.select(sankeyEl).append('div')
            .style('position', 'absolute')
            .style('pointer-events', 'none')
            .style('opacity', '0')
            .style('background', 'rgba(30,55,101,0.96)')
            .style('color', '#fff')
            .style('font-family', 'OpenSans')
            .style('font-size', '12px')
            .style('line-height', '1.4')
            .style('padding', '8px 10px')
            .style('border-radius', '6px')
            .style('border', '1px solid #6FC7EA')
            .style('box-shadow', '0 4px 14px rgba(0,0,0,0.35)')
            .style('z-index', '5')
            .style('max-width', '260px');

        const xL0 = 0, xL1 = nodeW, xR0 = W - nodeW;
        const maxTotal = Math.max(lowTotal, highTotal);

        // Total drawable height for each side, proportional to firm count
        const totalHL = lowTotal  > 0 ? (lowTotal  / maxTotal) * usableH : 0;
        const totalHR = highTotal > 0 ? (highTotal / maxTotal) * usableH : 0;

        // Center both sides vertically so neither floats to top
        let yL = marginY + (usableH - totalHL) / 2;
        let yR = marginY + (usableH - totalHR) / 2;

        sizeCategoryOrder.forEach((label) => {
            const lo = lowItems.find(d => d.size === label);
            const hi = highItems.find(d => d.size === label);
            const vL = lo ? (lo[metricDef.id] ?? 0) : 0;
            const vH = hi ? (hi[metricDef.id] ?? 0) : 0;
            const hL = lowTotal  > 0 ? (vL / lowTotal)  * totalHL : 0;
            const hR = highTotal > 0 ? (vH / highTotal) * totalHR : 0;
            const color = catColors[label];

            const lT = yL, lB = yL + hL;
            const rT = yR, rB = yR + hR;
            const xc = (xL1 + xR0) / 2;

            const path = [
                `M ${xL1} ${lT}`,
                `C ${xc} ${lT}, ${xc} ${rT}, ${xR0} ${rT}`,
                `L ${xR0} ${rB}`,
                `C ${xc} ${rB}, ${xc} ${lB}, ${xL1} ${lB}`,
                `Z`
            ].join(' ');

            // percentage of each year's total
            const pctL = lowTotal  ? ((vL / lowTotal)  * 100).toFixed(1) : '0.0';
            const pctH = highTotal ? ((vH / highTotal) * 100).toFixed(1) : '0.0';

            // tooltip HTML — firms metric shows count + %, percent metrics show just %
            const tipHtml = metricDef.id === 'amount'
                ? `<div style="font-weight:600;margin-bottom:4px">${label}</div>
                <div>${yearLow}: ${vL.toLocaleString()} firms (${pctL}%)</div>
                <div>${yearHigh}: ${vH.toLocaleString()} firms (${pctH}%)</div>`
                : `<div style="font-weight:600;margin-bottom:4px">${label}</div>
                <div>${metricDef.label}</div>
                <div>${yearLow}: ${vL.toFixed(1)}%</div>
                <div>${yearHigh}: ${vH.toFixed(1)}%</div>`;

            const band = svg.append('path').attr('d', path)
                .attr('fill', color).attr('fill-opacity', 0.5).attr('stroke', 'none')
                .style('cursor', 'pointer');

            band
                .on('mouseenter', () => {
                    band.attr('fill-opacity', 0.8);
                    tip.html(tipHtml).style('opacity', '1');
                })
                .on('mousemove', (event) => {
                    // position relative to the container
                    const rect = sankeyEl.getBoundingClientRect();
                    const x = event.clientX - rect.left;
                    const y = event.clientY - rect.top;
                    tip.style('left', `${x + 14}px`).style('top', `${y + 14}px`);
                })
                .on('mouseleave', () => {
                    band.attr('fill-opacity', 0.5);
                    tip.style('opacity', '0');
                });

            // node bars
            svg.append('rect').attr('x', xL0).attr('y', lT).attr('width', nodeW).attr('height', hL).attr('fill', color);
            svg.append('rect').attr('x', xR0).attr('y', rT).attr('width', nodeW).attr('height', hR).attr('fill', color);

            // left label
            svg.append('text').attr('x', xL1 + 6).attr('y', lT + hL / 2)
                .attr('dominant-baseline', 'middle')
                .attr('font-family', 'OpenSans').attr('font-size', 11).attr('fill', '#fff')
                .style('pointer-events', 'none')
                .text(sizeLabels[label] ?? label);

            yL += hL + padBetween;
            yR += hR + padBetween;
        });
    }

    async function loadData() {
        try {
            const [resLoc, resGoods, resSize] = await Promise.all([
                fetch(`${base}/data/B1B2B3.csv`),
                fetch(`${base}/data/B4renamed_normalized.csv`),
                fetch(`${base}/data/SIZE.csv`)
            ]);

            if (!resLoc.ok || !resGoods.ok || !resSize.ok) throw new Error('Failed to load dataset(s)');

            const csvLoc = await resLoc.text();
            const csvGoods = await resGoods.text();
            const csvSize = await resSize.text();

            b1Data = csvParse(csvLoc).map((row) => ({
                category: normalizeCategory(row['Type of Sale'].trim()),
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

        } catch (error) {
            console.error('Error loading survey data:', error);
            loadError = 'Unable to load sales data.';
        } finally {
            isLoading = false;
        }
    }
    
    // $: locTotal = locFiltered.reduce((sum, d) => sum + d.amount, 0);

    // Remove locYear filter, group by category across all years
    $: locAllYears = selectedYears.map(y => {
        const items = b1Data.filter(d => d.year === y);
        const total = items.reduce((sum, d) => sum + d.amount, 0);
        return { year: y, items, total };
    });

    // Get all unique categories across all years, sorted by most recent year amount
    $: allCategories = (() => {
        const latestYear = Math.max(...years);
        const latestItems = b1Data.filter(d => d.year === latestYear);
        const cats = [...new Set(b1Data.map(d => d.category))];
        return cats.sort((a, b) => {
            const aVal = latestItems.find(d => d.category === a)?.amount ?? 0;
            const bVal = latestItems.find(d => d.category === b)?.amount ?? 0;
            return bVal - aVal;
        });
    })();

    $: {
        const _m = waffleMetric;
        const _y = selectedYears;
        if (!isLoading) setTimeout(renderSankey, 50);
    }
        

    // ---------------------------
    // Goods/Services Spider Data (B4)
    // ---------------------------
    $: b4ByYear = selectedYears.map((y) => {
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
            const labels = items.map((d) => shortB4Label(d.category));
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


			const brandLightBlue = resolveCssColor('--brandLightBlue') || '#6FC7EA';
            const brandWhite = resolveCssColor('--brandWhite') || '#ffffff';

            const data = [
                {
                    type: 'scatterpolar',
                    r: activeValues,
                    theta: labels,
                    fill: 'toself',
                    mode: 'lines+markers',
                    name: String(year),
                    marker: { color: brandLightBlue, size: 8, symbol: 'circle' },
                    line: { color: brandLightBlue },
                    fillcolor: hexToRgba(brandLightBlue.replace('#','').length === 6 ? brandLightBlue : '#6FC7EA', 0.15),
                    hoverinfo: 'text',
                    hovertemplate: hovertemplate,
                    text: fullLabels,
                    hoverlabel: {
                        bgcolor: '#1e3765',
                        bordercolor: brandLightBlue,
                        font: { family: 'OpenSans', size: 12, color: brandWhite },
                        namelength: -1
                    }
                }
            ];

            const layout = {
                polar: {
                    bgcolor: 'rgba(0,0,0,0)',
                    radialaxis: {
                        visible: true,
                        ticksuffix: spiderViewMode === 'percent' ? '%' : '',
                        color: 'rgba(255,255,255,0.6)',
                        gridcolor: 'rgba(255,255,255,0.12)',
                        linecolor: 'rgba(255,255,255,0.2)',
                        tickfont: { color: 'rgba(255,255,255,0.7)', family: 'OpenSans', size: 10 }
                    },
                    angularaxis: {
                        tickfont: { size: 10, family: 'OpenSans', color: 'rgba(255,255,255,0.85)' },
                        gridcolor: 'rgba(255,255,255,0.12)',
                        linecolor: 'rgba(255,255,255,0.2)'
                    }
                },
                title: {
                    text: `${year}`,
                    font: { family: 'TradeGothicBold', size: 18, color: brandLightBlue }
                },
                showlegend: false,
                margin: { l: 80, r: 80, t: 40, b: 60 },
                height: 400,
                autosize: true,
                paper_bgcolor: 'rgba(0,0,0,0)',
                plot_bgcolor: 'rgba(0,0,0,0)',
                hovermode: 'closest'
            };

            const config = { displayModeBar: false, responsive: true, staticPlot: false};
            Plotly.react(el, data, layout, config);
        });
    }

    onMount(() => {
        loadData();
    });

    $: {
        const _mode = spiderViewMode;
        const _data = b4ByYear;
        if (!isLoading) {
            // Small timeout ensures DOM targets exist before plotting
            setTimeout(renderCharts, 50);
        }
    }

    $: if (yearB === yearA) {
        yearB = years.find(y => y !== yearA) ?? years[0];
    }
</script>

<Password />

<Logo logoType="White" backgroundColor="var(--brandGray90)"/>

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

        <!-- SHARED YEAR COMPARISON SELECTOR -->
        <div class="text">
            <div class="filter-group inline-filters">
                <span class="filter-label">Compare years (applies to all charts below)</span>
                <div class="year-pair">
                    <select class="year-select" bind:value={yearA}>
                        {#each years as y}
                            <option value={y}>{y}</option>
                        {/each}
                    </select>
                    <span class="year-vs">vs</span>
                    <select class="year-select" bind:value={yearB}>
                        {#each years.filter(y => y !== yearA) as y}
                            <option value={y}>{y}</option>
                        {/each}
                    </select>
                </div>      
            </div>
        </div>
        

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
            {#each selectedYears as y}
                <div class="spider-chart" bind:this={chartEls[y]}></div>
            {/each}
        </div>

        <!-- TOP CONTROLS & TOTAL EXPENDITURE -->
        <!-- <div class="text">
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
        </div> -->

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
                <select class="year-select" bind:value={selectedRegion}>
                    {#each regions as r}
                        <option value={r}>{regionLabels[r]}</option>
                    {/each}
                </select>
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
                        {#each allCategories.filter(cat => selectedRegion === 'all' || resolveRegion(cat) === selectedRegion || (selectedRegion === 'notcanada' && resolveRegion(cat) === 'notcanada')) as cat}
                            <tr>
                                <td class="align-left cell-category">{cat}</td>
                                {#each locAllYears as { items, total }}
                                    {@const val = items.find(d => d.category === cat)?.amount ?? 0}
                                    <td>{val > 0 ? formatValue(val, total, locViewMode) : '—'}</td>
                                {/each}
                            </tr>
                        {/each}
                        <tr class="total-row">
                            <td class="align-left cell-category">Total</td>
                            {#each locAllYears as { total, items }}
                                {@const filteredTotal = items
                                    .filter(d => selectedRegion === 'all' || resolveRegion(d.category) === selectedRegion || (selectedRegion === 'notcanada' && resolveRegion(d.category) === 'notcanada'))
                                    .reduce((sum, d) => sum + d.amount, 0)}
                                <td>{formatValue(filteredTotal, filteredTotal, locViewMode)}</td>
                            {/each}
                        </tr>
                    </tbody>
                </table>
            </div>
        </div>

        <div class="text">
            <h3>Share of sales by company size</h3>
<!--             
            <div class="waffle-legend" style="margin-top: 16px; margin-bottom: 8px;">
                {#each sizeCategoryOrder as label}
                    <div class="waffle-legend-row">
                        <span class="waffle-swatch" style="background-color: {resolveCssColor(sizeCategoryColors[label])}"></span>
                        <span class="waffle-label">{label}</span>
                    </div>
                {/each}
            </div> -->
                <p>Flow of {sizeMetricOptions.find(m => m.id === waffleMetric)?.label.toLowerCase()} by company size across the two selected years.</p>
                <div class="filter-group inline-filters">
                    <span class="filter-label">Metric</span>
                    <select class="year-select" bind:value={waffleMetric}>
                        {#each sizeMetricOptions as metric}
                            <option value={metric.id}>{metric.label}</option>
                        {/each}
                    </select>
                </div>
                <div class="sankey-chart" bind:this={sankeyEl}></div>
            </div>
    {/if}
</main>

<Footer />

<style>
    .sankey-chart {
        width: 100%;
        height: 420px;
        position: relative;
    }
    .year-pair {
        display: flex;
        align-items: center;
        gap: 10px;
    }

    .year-vs {
        font-family: OpenSansBold;
        font-size: 13px;
        color: var(--brandGray);
    }
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


    .filter-group { display: flex; flex-direction: column; gap: 8px; margin-bottom: 8px;}

    .filter-label { font-family: OpenSansBold; font-size: 13px; color: var(--brandWhite); }

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
        border: 1px solid var(--brandWhite);
        background-color: var(--brandGray90);
        border-radius: 3px;
        font-family: OpenSans;
        font-size: 14px;
        min-width: 120px;
        color: var(--brandWhite);
    }

    /* Spider Charts Scroll View */
    .spider-scroll-wrapper {
        display: flex;
        overflow-x: hidden;        /* no scroll — constrained to text width */
        gap: 16px;
        /* padding-bottom: 16px; */
        /* border-left: 1px solid var(--brandGray);
        border-right: 1px solid var(--brandGray); */
        width: 100%;
        box-sizing: border-box;
    }

    .spider-chart {
        flex: 1 1 0;              
        min-width: 0;
        height: 400px;             
        border: 1px solid var(--brandGray);
        background-color: var(--brandGray90);
        border-radius: 3px;
    }

    /* Simple Shared Table */
    .table-wrap {
        width: 100%;
        margin: 0 auto;
        overflow-x: auto;
        border: 1px solid var(--brandGray);
        border-radius: 3px;
        background: var(--brandGray90);
    }

    .data-table {
        width: 100%;
        margin: 0 auto;
        border-collapse: collapse;
        font-family: OpenSans;
        font-size: 14px;
    }

    .data-table th, .data-table td {
        color: var(--brandWhite);
        padding: 6px 8px;
        border-bottom: 1px solid var(--brandGray);
        text-align: right;
    }

    .data-table th:first-child,
    .data-table td:first-child {
        border-right: 1px solid var(--brandGray);
    }

    .data-table th { background:var(--brandGray90); font-family: OpenSansBold}
    .align-left { text-align: left !important; }
    .cell-category { min-width: 300px;  font-family: OpenSans; }
    .data-table tbody tr:last-child td { border-bottom: none; }

    .total-row {
        font-family: OpenSansBold;
    }

    .inline-filters {
        margin-top: 12px;
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
        color: var(--brandWhite);
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