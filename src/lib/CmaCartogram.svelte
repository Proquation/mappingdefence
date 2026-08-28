<script>
	import { onDestroy, onMount } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import * as d3 from 'd3';
	import { base } from '$app/paths';
	import { UNDER, MID, OVER, SEQ_LO, SEQ_HI } from '$lib/cartogram-colours.js';

	export let rows = [];
	export let cmaGeojson = null;
	export let provinceGeojson = null;
	export let lqBasis = 'sales';
	export let formatSales = (v) => `${v}`;
	export let usGeojson = null;
	export let darkMode = true;
	export let colourType = 'lq';
	export let militaryGeojson = null;
	export let showMilitaryBases = false;

	let map, mapContainer, mapLoaded = false, popup, markerLayer;

	export let compareRows = [];

	const PROVINCE_ORDER = [
		'Newfoundland and Labrador',
		'Prince Edward Island',
		'Nova Scotia',
		'New Brunswick',
		'Quebec',
		'Ontario',
		'Manitoba',
		'Saskatchewan',
		'Alberta',
		'British Columbia',
		'Nunavut',
		'Northwest Territories',
		'Yukon'
	];

	const PROVINCE_RURAL_UID = {
		'Newfoundland and Labrador': 'RURAL_NL',
		'Prince Edward Island': 'RURAL_PE',
		'Nova Scotia': 'RURAL_NS',
		'New Brunswick': 'RURAL_NB',
		'Quebec': 'RURAL_QC',
		'Ontario': 'RURAL_ON',
		'Manitoba': 'RURAL_MB',
		'Saskatchewan': 'RURAL_SK',
		'Alberta': 'RURAL_AB',
		'British Columbia': 'RURAL_BC',
		'Nunavut': 'RURAL_NU',
		'Northwest Territories': 'RURAL_NT',
		'Yukon': 'RURAL_YT'
	};

	$: compareLqByUid = (() => {
		const m = {};
		compareRows.forEach(r => {
			const v = r[lqField];
			m[r.region_uid] = Number.isFinite(v) ? v : null;
		});
		return m;
	})();

	const PIN_ICON = `${base}/img/pin_icon.svg`;

	// const MIL_ICONS = {
	// 	'Canadian Army': `${base}/img/Badge_of_the_Canadian_Army.svg`,
	// 	'Royal Canadian Airforce': `${base}/img/Badge_of_the_RCAF.svg`,
	// 	'Royal Canadian Navy': `${base}/img/Badge_of_the_Royal_Canadian_Navy.svg`,
	// 	'All Services': `${base}/img/Badge_of_the_Canadian_Armed_Forces.png`
	// };
	
	const RURAL_POINTS = {
		RURAL_ON: [-84.5, 49.5],
		RURAL_QC: [-72.0, 52.0],
		RURAL_BC: [-124.5, 54.5],
		RURAL_AB: [-114.5, 55.5],
		RURAL_SK: [-106.5, 54.5],
		RURAL_MB: [-98.5, 55.0],
		RURAL_NS: [-63.0, 45.0],
		RURAL_NB: [-66.5, 46.5],
		RURAL_NL: [-60.0, 53.0],
		RURAL_PE: [-63.2, 46.3],
		RURAL_NT: [-120.0, 64.5],
		RURAL_YT: [-135.0, 63.0],
		RURAL_NU: [-94.0, 66.0]
	};

	let centroidByUid = {};

	$: mapBg      = darkMode ? '#333333' : '#e8e8e8';
	$: provFill   = darkMode ? '#1a1a1a' : '#F2F2F2';
	$: provLine   = darkMode ? '#333333' : '#b0b0b0';
	$: usFill     = darkMode ? '#1a1a1a' : '#F2F2F2';
	$: usLine     = darkMode ? '#333333' : '#a8a8a8';
	$: noDataColor = darkMode ? '#666666' : '#666666';
	$: labelColor = darkMode ? '#ffffff' : '#111111';
	$: labelShadow = darkMode ? '0 1px 3px rgba(0,0,0,0.8)' : '0 1px 2px rgba(255,255,255,0.8)';

	$: if (mapLoaded) {
		map.setPaintProperty('background', 'background-color', mapBg);
		if (map.getLayer('prov-fill')) map.setPaintProperty('prov-fill', 'fill-color', provFill);
		if (map.getLayer('prov-line')) map.setPaintProperty('prov-line', 'line-color', provLine);
		if (map.getLayer('us-fill'))  map.setPaintProperty('us-fill',  'fill-color', usFill);
		if (map.getLayer('us-line'))  map.setPaintProperty('us-line',  'line-color', usLine);
		drawBubbles();
	}

	$: if (mapLoaded && usGeojson) addUsLayer();
	$: if (mapLoaded && provinceGeojson) addProvinceLayer();

	function addUsLayer() {
		if (!map) return;
		if (map.getSource('us')) {
			map.getSource('us').setData(usGeojson);
			return;
		}
		const beforeLayer = map.getLayer('prov-fill') ? 'prov-fill' : undefined;
		map.addSource('us', { type: 'geojson', data: usGeojson });
		map.addLayer({ id: 'us-fill', type: 'fill', source: 'us',
			paint: { 'fill-color': usFill, 'fill-opacity': 1 } }, beforeLayer);
		map.addLayer({ id: 'us-line', type: 'line', source: 'us',
			paint: { 'line-color': usLine, 'line-width': 0.5 } }, beforeLayer);
	}

	function computeCentroids() {
		const c = {};
		if (cmaGeojson) {
			for (const f of cmaGeojson.features) {
				const uid = String(f.properties.region_uid);
				c[uid] = polygonCentroid(f.geometry);
			}
		}
		Object.assign(c, Object.fromEntries(Object.entries(RURAL_POINTS)));
		centroidByUid = c;
	}

	function polygonCentroid(geom) {
		let x = 0, y = 0, n = 0;
		const walk = (coords) => {
			if (typeof coords[0] === 'number') { x += coords[0]; y += coords[1]; n++; }
			else coords.forEach(walk);
		};
		walk(geom.coordinates);
		return n ? [x / n, y / n] : [-95, 55];
	}

	function shortCmaName(name) {
		if (!name) return '';
		return name.replace(/\s*[-–]\s*[A-Z]{2}$/, '').replace(/\s*\(CMA\).*$/, '').trim();
	}

	$: lqField = { sales: 'lq_sales', firms: 'lq_firms', jobs: 'lq_jobs' }[lqBasis];

	$: bubbles = (() => {
		if (!mapLoaded || !rows.length) return [];
		return rows
			.filter((r) => centroidByUid[r.region_uid])
			.map((r) => {
				const firms = (r.suppressed === true || r.suppressed === 'True') ? 0 : Number(r.n_firms) || 0;
				const sales = Number.isFinite(r.total_sales_M) ? r.total_sales_M : 0;
				const jobs  = Number.isFinite(r.total_jobs) ? r.total_jobs : 0;
				const absBasis = lqBasis === 'jobs' ? jobs : lqBasis === 'firms' ? firms : sales;
				const lqVal = Number.isFinite(r[lqField]) ? r[lqField] : null;
				const compareLq = compareLqByUid[r.region_uid] ?? null;
				const lqDiff = (Number.isFinite(lqVal) && Number.isFinite(compareLq)) ? lqVal - compareLq : null;
				return {
					uid: r.region_uid,
					name: r.region_name,
					sales, firms, jobs,
					n_firms: r.n_firms,
					total_jobs: r.total_jobs,
					avg_employees: r.avg_employees,
					suppressed: r.suppressed === true || r.suppressed === 'True',
					lngLat: centroidByUid[r.region_uid],
					lq: lqVal,
					lqDiff,
					colorVal: colourType === 'totals' ? absBasis : colourType === 'yoy' ? lqDiff : lqVal,
					sizeVal: colourType === 'totals' ? (lqVal ?? 0) : absBasis
				};
			});
	})();

	$: yoyClamp = (() => {
		const vals = bubbles.map(b => b.lqDiff).filter(v => Number.isFinite(v)).map(Math.abs).sort((a, b) => a - b);
		if (!vals.length) return 1;
		return Math.max(0.1, vals[Math.floor(vals.length * 0.95)] ?? vals[vals.length - 1]);
	})();

	function yoyColor(diff) {
		if (diff == null) return noDataColor;
		if (diff >= 0) {
			const t = Math.min(1, diff / yoyClamp);
			return d3.interpolateRgb(MID, OVER)(t);
		}
		const t = Math.min(1, -diff / yoyClamp);
		return d3.interpolateRgb(MID, UNDER)(t);
	}

	function colorFor(b) {
		if (colourType === 'totals') {
			if (b.suppressed || !(b.colorVal > 0)) return noDataColor;
			const t = Math.min(1, b.colorVal / Math.max(1, absClamp));
			return d3.interpolateRgb(SEQ_LO, SEQ_HI)(t);
		}
		if (colourType === 'yoy') return yoyColor(b.lqDiff);
		return lqColor(b.colorVal);
	}

	function lqColor(lq) {
		if (lq == null) return noDataColor;
		if (lq >= 1) {
			const t = Math.min(1, (lq - 1) / (lqClamp - 1));
			return d3.interpolateRgb(MID, OVER)(t);
		}
		const t = Math.min(1, (1 - lq) / (1 - 1 / lqClamp));
		return d3.interpolateRgb(MID, UNDER)(t);
	}

	$: cmaBubbles = bubbles.filter(b => !String(b.uid).startsWith('RURAL_'));
	$: ruralBubbles = bubbles.filter(b => String(b.uid).startsWith('RURAL_'));

	$: ruralTableRows = PROVINCE_ORDER.map((prov) => {
		const uid = PROVINCE_RURAL_UID[prov];
		const match = ruralBubbles.find((b) => b.uid === uid);
		if (match) {
			return { ...match, name: prov }; // force the display name to the clean province name
		}
		return {
			uid,
			name: `${prov}`,
			lq: null,
			sales: null,
			total_jobs: null,
			n_firms: null,
			suppressed: false
		};
	});

	$: totalMetric = (() => {
		if (lqBasis === 'sales') return cmaBubbles.map(b => b.sales).filter(Number.isFinite).reduce((s, v) => s + v, 0);
		if (lqBasis === 'jobs')  return cmaBubbles.map(b => b.total_jobs).filter(Number.isFinite).reduce((s, v) => s + v, 0);
		return cmaBubbles.filter(b => !b.suppressed).map(b => Number(b.n_firms) || 0).reduce((s, v) => s + v, 0);
	})();

	$: totalLabel   = lqBasis === 'sales' ? 'Total sales (shown, excl. rural)' : lqBasis === 'jobs' ? 'Total jobs (shown, excl. rural)' : 'Total firms (shown, excl. rural)';
	$: totalDisplay = lqBasis === 'sales' ? formatSales(totalMetric) : totalMetric.toLocaleString();

	$: lqClamp = (() => {
		const vals = bubbles.map((b) => b.lq).filter((v) => Number.isFinite(v)).sort((a, b) => a - b);
		if (!vals.length) return 3;
		return Math.max(1, vals[Math.floor(vals.length * 0.95)] ?? vals[vals.length - 1]);
	})();

	$: sizeClamp = (() => {
		const vals = bubbles.map(b => b.sizeVal).filter(v => v > 0).sort((a,b)=>a-b);
		if (!vals.length) return 1;
		return vals[Math.floor(vals.length * 0.95)] ?? vals[vals.length-1];
	})();

	$: absClamp = (() => {
		const vals = bubbles.map(b => b.colorVal).filter(v => v > 0).sort((a,b)=>a-b);
		if (!vals.length) return 1;
		return vals[Math.floor(vals.length*0.95)] ?? vals[vals.length-1];
	})();

	function radiusPx(v) {
		const t = Math.sqrt(Math.min(v, sizeClamp) / sizeClamp);
		return 3 + t * 25;
	}

	function formatSizeVal(v) {
		if (colourType === 'totals') return v.toFixed(2);
		if (lqBasis === 'sales') return formatSales(v);
		return Math.round(v).toLocaleString();
	}

	const MAX_LEGEND_R = 40;

	$: sizeLegendSteps = (() => {
		if (!sizeClamp) return [];
		const steps = [0.1, 0.25, 0.5, 1];
		return steps.map(t => {
			const val = sizeClamp * t;
			const baseR = radiusPx(val);
			return { val, r: Math.min(Math.max(3, baseR * currentZoomScale), MAX_LEGEND_R) };
		});
	})();

	function project(lngLat) { return map.project(lngLat); }

	function addProvinceLayer() {
		if (!map) return;
		if (map.getSource('prov')) {
			map.getSource('prov').setData(provinceGeojson);
			return;
		}
		map.addSource('prov', { type: 'geojson', data: provinceGeojson });
		map.addLayer({ id: 'prov-fill', type: 'fill', source: 'prov',
			paint: { 'fill-color': provFill, 'fill-opacity': 1 } });
		map.addLayer({ id: 'prov-line', type: 'line', source: 'prov',
			paint: { 'line-color': provLine, 'line-width': 0.8, 'line-opacity': 0.9 } });
		drawBubbles();
	}

	function drawMilitaryPoints(g) {
		if (!showMilitaryBases || !militaryGeojson) return;
		const ICON_SIZE = 16;
		const milNodes = militaryGeojson.features.map(f => {
			const p = map.project(f.geometry.coordinates);
			return { x: p.x, y: p.y, name: f.properties.Name, type: f.properties.Type };
		});

		g.selectAll('image.mil-marker')
			.data(milNodes)
			.join('image')
			.attr('class', 'mil-marker')
			.attr('href', d => PIN_ICON)
			.attr('x', d => d.x - ICON_SIZE / 2)
			.attr('y', d => d.y - ICON_SIZE)
			.attr('width', ICON_SIZE)
			.attr('height', ICON_SIZE)
			.style('cursor', 'pointer')
			.on('mouseenter', (event, d) => {
				if (popup) popup.remove();
				const lngLat = map.unproject([d.x, d.y]);
				popup = new maplibregl.Popup({ closeButton: false })
					.setLngLat(lngLat)
					.setHTML(`<div style="font-family:OpenSans,sans-serif;font-size:12px;background:#1e2433;color:#fff;padding:6px 10px;border-radius:6px;">
						<b>${d.name}</b><br>${d.type}</div>`)
					.addTo(map);
			})
			.on('mouseleave', () => { if (popup) { popup.remove(); popup = null; } });
	}

	
	let currentZoomScale = 1;

	function drawBubbles() {
		if (!mapLoaded || !markerLayer) return;
		const zoom = map.getZoom();
		const zoomScale = Math.max(0.1, (zoom - 2) / 2);
		const labelMinR = zoom < 2 ? 999 : zoom < 4 ? 18 : zoom < 5.5 ? 12 : 8;
		const svg = d3.select(markerLayer);
		currentZoomScale = zoomScale;  // ← add this
		svg.selectAll('*').remove();

		const allNodes = cmaBubbles.map((b) => {
			const p = project(b.lngLat);
			const baseR = radiusPx(b.sizeVal);
			return { ...b, x: p.x, y: p.y, r: Math.max(3, baseR * zoomScale) };
		});

		const g = svg.append('g');

		const node = g.selectAll('g.bubble')
			.data(allNodes)
			.join('g').attr('class', 'bubble')
			.attr('transform', (d) => `translate(${d.x},${d.y})`)
			.style('cursor', 'pointer')
			.on('mouseenter', (event, d) => showPopup(d))
			.on('mouseleave', () => { if (popup) { popup.remove(); popup = null; } });

		node.append('circle')
			.attr('r', (d) => d.r)
			.attr('fill', (d) => colorFor(d))
			.attr('stroke', darkMode ? 'rgba(255,255,255,0.2)' : 'rgba(0,0,0,0.15)')
			.attr('stroke-width', 0.6)
			.attr('fill-opacity', 0.85);

		node.filter((d) => d.r >= labelMinR)
			.append('text')
			.attr('text-anchor', 'middle')
			.attr('dy', '0.35em')
			.style('font-family', 'OpenSansBold')
			.style('font-size', (d) => `${Math.min(11, Math.max(8, d.r * 0.35))}px`)
			.style('fill', labelColor)
			.style('pointer-events', 'none')
			.style('text-shadow', labelShadow)
			.text((d) => shortCmaName(d.name));

		drawMilitaryPoints(g);
	}

	function showPopup(d) {
		if (popup) popup.remove();
		const yoyTxt = d.lqDiff == null ? 'N/A' : (d.lqDiff >= 0 ? '+' : '') + d.lqDiff.toFixed(2);

		function firmsTxt(n_firms) {
			if (n_firms === '0' || n_firms == null) return 'No firms';
			if (n_firms === '<2') return '1 firm (suppressed)';
			return `${Number(n_firms).toLocaleString()} firms`;
		}

		const noData = (d.n_firms === '0' || d.n_firms == null);
		const lqTxt = noData ? 'No data' : d.lq == null ? 'Suppressed' : d.lq.toFixed(2);

		let rows;
		if (lqBasis === 'firms') {
			rows = `<div>LQ (firms): ${lqTxt}</div><div>LQ change: ${yoyTxt}</div><div>Firms: ${firmsTxt(d.n_firms)}</div>`;
		} else if (lqBasis === 'jobs') {
			const jobsTxt = d.total_jobs == null ? 'N/A' : Number(d.total_jobs).toLocaleString();
			rows = `<div>LQ (jobs): ${lqTxt}</div><div>LQ change: ${yoyTxt}</div><div>Total jobs: ${jobsTxt}</div><div>Firms: ${firmsTxt(d.n_firms)}</div>`;
		} else {
			const salesTxt = d.suppressed ? 'Suppressed' : formatSales(d.sales);
			rows = `<div>LQ (sales): ${lqTxt}</div><div>LQ change: ${yoyTxt}</div><div>Sales: ${salesTxt}</div><div>Firms: ${firmsTxt(d.n_firms)}</div>`;
		}

		const popupLngLat = map.unproject([d.x, d.y]);
		popup = new maplibregl.Popup({ closeButton: false, closeOnClick: true })
			.setLngLat(popupLngLat)
			.setHTML(`<div style="font-family:OpenSans,sans-serif;font-size:13px;line-height:1.6;background:#1e2433;color:#e0e0e0;padding:10px;border-radius:8px;">
				<div style="font-weight:600;margin-bottom:4px;color:#ffffff;">${d.name}</div>
				${rows}
			</div>`)
			.addTo(map);
	}

	$: if (mapLoaded && (bubbles || colourType || darkMode || showMilitaryBases || militaryGeojson)) drawBubbles();

	onMount(() => {
		map = new maplibregl.Map({
			container: mapContainer,
			style: {
				version: 8,
				glyphs: 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
				sources: {},
				layers: [{ id: 'background', type: 'background', 
					paint: { 'background-color': darkMode ? '#333333' : '#e8e8e8' } }]
			},
			center: [-95, 53], zoom: 3.2, minZoom: 2, maxZoom: 10,
			attributionControl: false,
			projection: 'globe'
		});
		map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'bottom-left');

		map.on('load', () => {
			const overlay = document.createElement('div');
			overlay.style.cssText = 'position:absolute;inset:0;pointer-events:none;';
			const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
			svg.style.cssText = 'width:100%;height:100%;pointer-events:none;';
			svg.addEventListener('mousedown', (e) => e.stopPropagation(), false);
			overlay.appendChild(svg);
			mapContainer.appendChild(overlay);
			markerLayer = svg;

			overlay.addEventListener('wheel', (e) => {
				e.preventDefault();
				const rect = mapContainer.getBoundingClientRect();
				const point = [e.clientX - rect.left, e.clientY - rect.top];
				const zoomDelta = -e.deltaY * 0.005; // tune sensitivity to taste
				map.zoomTo(map.getZoom() + zoomDelta, { around: map.unproject(point) });
			}, { passive: false });
			
			const mo = new MutationObserver(() => {
				svg.querySelectorAll('circle, image').forEach((c) => (c.style.pointerEvents = 'auto'));
			});
			mo.observe(svg, { childList: true, subtree: true });

			computeCentroids();
			mapLoaded = true;
			drawBubbles();

			map.on('move', drawBubbles);
		});

		map.on('style.load', () => {
			map.setProjection({ type: map.getZoom() < 7 ? 'globe' : 'mercator' });
		});
		map.on('zoom', () => {
			map.setProjection({ type: map.getZoom() < 7 ? 'globe' : 'mercator' });
			drawBubbles();
			currentZoomScale = currentZoomScale;
		});

	});

	onDestroy(() => { if (popup) popup.remove(); if (map) map.remove(); map = null; });
</script>

<div class="map-row">
    <div class="map-wrapper" class:light={!darkMode}>
        <div class="map" bind:this={mapContainer}></div>
        <div class="total-overlay"
            style="background:{darkMode ? '#1e2433' : '#ffffff'}; border-color:{darkMode ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.15)'};">
            <div class="total-label" style="color:{darkMode ? 'rgba(255,255,255,0.6)' : 'rgba(0,0,0,0.5)'};">{totalLabel}</div>
            <div class="total-value" style="color:{darkMode ? '#ffffff' : '#111111'};">{totalDisplay}</div>
        </div>
    </div>

    <div class="side-panel"
		style="background:{darkMode ? '#1e2433' : '#ffffff'}; border-color:{darkMode ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.15)'};">
		<div class="size-legend-title" style="color:{darkMode ? '#ffffff' : '#111111'};">
			Bubble size — {colourType === 'totals' ? 'LQ' : lqBasis}
		</div>
		<div class="size-legend-items">
			{#each sizeLegendSteps as step}
				<div class="size-legend-item">
					<svg width={step.r * 2 + 4} height={step.r * 2 + 4}>
						<circle
							cx={step.r + 2} cy={step.r + 2} r={step.r}
							fill="none"
							stroke={darkMode ? 'rgba(255,255,255,0.5)' : 'rgba(0,0,0,0.4)'}
							stroke-width="1"
						/>
					</svg>
					<span style="color:{darkMode ? 'rgba(255,255,255,0.85)' : 'rgba(0,0,0,0.75)'};">{formatSizeVal(step.val)}</span>
				</div>
			{/each}
		</div>
	</div>
</div>

<div class="under-map">
	Note: All dollar amounts are displayed in constant dollars (2025)
</div>

<div class="legend-bar">
	<div class="legend-inner">
   	{#if colourType === 'totals'}
		<div class="legend-title">Total {lqBasis}</div>
		<div class="ramp-wrap">
			<div class="ramp" style="background: linear-gradient(to right, {SEQ_LO} 0%, {SEQ_HI} 100%)"></div>
			<div class="ticks">
				<span style="left:0%">{lqBasis === 'sales' ? formatSales(0) : '0'}</span>
				<span style="left:50%">{lqBasis === 'sales' ? formatSales(absClamp / 2) : Math.round(absClamp / 2).toLocaleString()}</span>
				<span style="left:100%">{lqBasis === 'sales' ? formatSales(absClamp) : Math.round(absClamp).toLocaleString()}+</span>
			</div>
		</div>
	{:else if colourType === 'yoy'}
		<div class="legend-title">Change in LQ ({lqBasis})</div>
		<div class="ramp-wrap">
			<div class="ramp" style="background: linear-gradient(to right, {UNDER} 0%, {MID} 50%, {OVER} 100%)"></div>
			<div class="ticks">
				<span style="left:0%">−{yoyClamp.toFixed(2)}</span>
				<span style="left:50%" class="tick-strong">0</span>
				<span style="left:100%">+{yoyClamp.toFixed(2)}</span>
			</div>
		</div>
		<div class="legend-note">Positive = LQ increased between the two selected years</div>
	{:else}
		<div class="legend-title">Location quotient ({lqBasis})</div>
		<div class="ramp-wrap">
			<div class="ramp" style="background: linear-gradient(to right, {UNDER} 0%, {MID} 50%, {OVER} 100%)"></div>
			<div class="ticks">
				<span style="left:0%">{(1/lqClamp).toFixed(2)}</span>
				<span style="left:50%" class="tick-strong">1.0</span>
				<span style="left:100%">{lqClamp.toFixed(1)}</span>
			</div>
		</div>
		<div class="legend-note">1.0× = national average</div>
	{/if}
	</div>
</div>

{#if showMilitaryBases}
<div class="legend-bar" style="margin-top: 4px;">
    <div class="legend-inner">
        <div class="legend-title">Canadian Forces Base (CFB)</div>
        <div class="mil-legend-row">
			<div class="mil-legend-item">
				<img src={PIN_ICON} alt="DND Facility" class="mil-icon" />
			</div>
		</div>
    </div>
</div>
{/if}

<!-- Rural table -->
{#if ruralTableRows.length}
<div class="rural-table">
    <div class="rural-title">Rural regions (not shown on map)</div>
    <table>
        <thead>
            <tr>
                <th>Rural portion of province</th>
                <th>LQ ({lqBasis})</th>
                <th>{lqBasis === 'jobs' ? 'Jobs' : lqBasis === 'sales' ? 'Sales' : 'Firms'}</th>
                <th>Firms</th>
            </tr>
        </thead>
        <tbody>
           {#each ruralTableRows as b}
			<tr>
				<td>{b.name}</td>
				<td>{b.lq == null ? 'N/A' : b.lq.toFixed(2)}</td>
				<td>
					{#if lqBasis === 'jobs'}{b.total_jobs == null ? 'N/A' : Number(b.total_jobs).toLocaleString()}
					{:else if lqBasis === 'sales'}{b.sales == null ? 'N/A' : (b.suppressed ? 'Suppressed' : formatSales(b.sales))}
					{:else}{b.n_firms ?? 'N/A'}{/if}
				</td>
				<td>{b.n_firms ?? 'N/A'}</td>
			</tr>
			{/each}
        </tbody>
    </table>
</div>
{/if}

<style>
	:global(.maplibregl-popup-tip) {
		border-top-color: #1e2433 !important;
		border-bottom-color: #1e2433 !important;
	}	
	.mil-legend-row { display: flex; gap: 16px; flex-wrap: wrap; }
	.mil-legend-item { display: flex; align-items: center; gap: 6px; font-size: 12px; }
	.mil-icon { width: 16px; height: 16px; object-fit: contain; }
	.under-map { display: flex; font-family: OpenSans; font-size: 12px; color: var(--brandWhite); padding-top: 3px; }

	.map-row {
		display: flex;
		align-items: stretch;
		gap: 12px;
		max-width: 1600px;
		margin: 0 auto;
	}
	.map-wrapper {
		position: relative;
		flex: 1 1 auto;
		min-width: 0;
		height: 62vh; min-height: 460px;
		border: 1px solid rgba(255,255,255,0.1);
	}
	.total-overlay {
		position: absolute; top: 12px; left: 12px;
		border-radius: 6px; padding: 8px 12px; font-family: OpenSans;
		border: 1px solid;
	}
	.total-label { font-size: 11px; font-family: OpenSansBold; margin-bottom: 2px; }
	.total-value { font-size: 20px; font-family: TradeGothicBold; }

	.side-panel {
		flex: 0 0 120px;
		border: 1px solid;
		padding: 10px 14px;
		font-family: OpenSans;
		display: flex;
		flex-direction: column;
		align-items: center;
	}
	.size-legend-title {
		font-size: 11px;
		font-family: OpenSansBold;
		margin-bottom: 8px;
		text-align: center;
	}
	.size-legend-items {
		flex: 1;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 8px;
	}
	.size-legend-item {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 2px;
		font-size: 11px;
	}

	.total-overlay {
		position: absolute; top: 12px; left: 12px;
		background: #1e2433 ; border: 1px solid rgba(255,255,255,0.15);
		border-radius: 6px; padding: 8px 12px; font-family: OpenSans;
	}
	.total-label { font-size: 11px; color: rgba(255,255,255,0.6); font-family: OpenSansBold; margin-bottom: 2px; }
	.total-value { font-size: 20px; font-family: TradeGothicBold; color: #ffffff; }

	.rural-table {
		max-width: 680px; width: 100%; margin: 16px auto 0;
		font-family: OpenSans; font-size: 12px; color: var(--brandWhite);
	}
	.rural-title { font-family: OpenSansBold; margin-bottom: 8px; font-size: 13px; }
	.rural-table table { width: 100%; border-collapse: collapse; }
	.rural-table th {
		text-align: left; font-family: OpenSansBold; padding: 6px 8px;
		border-bottom: 1px solid rgba(255,255,255,0.2); font-size: 11px;
	}
	.rural-table td { padding: 5px 8px; border-bottom: 1px solid rgba(255,255,255,0.08); }
	.rural-table th:not(:first-child),
	.rural-table td:not(:first-child) { text-align: right; }
	.rural-table tr:hover td { background: rgba(255,255,255,0.04); }
	.legend-bar {
		max-width: 1080px; width: 100%; margin: 8px auto 0; padding: 8px 12px;
		font-family: OpenSans; font-size: 12px; color: var(--brandWhite);
		display: flex;
		flex-direction: column;
		align-items: center;
	}

	.legend-title { font-family: OpenSansBold; margin-bottom: 6px; align-self: flex-start; }
	.legend-note  { align-self: flex-start; }
	.legend-inner {
		width: 680px;
	}
	.ramp-wrap { position: relative; width: 100%; margin: 0 auto;}
	.ramp { width: 100%; height: 12px; border-radius: 2px; }
	.ticks { position: relative; height: 18px; margin-top: 2px; }
	.ticks span {
		position: absolute; transform: translateX(-50%);
		font-size: 11px; color: var(--brandWhite); white-space: nowrap;
	}
	.ticks span:first-child { transform: none; }
	.ticks span:last-child  { transform: translateX(-100%); }
	.ticks span.tick-strong { color: var(--brandWhite); }
	.ticks span.tick-strong::before {
		content: ''; position: absolute; bottom: 16px; left: 50%;
		width: 1px; height: 12px; background: var(--brandGray90);
	}
	.map-wrapper :global(.maplibregl-ctrl-bottom-left .maplibregl-ctrl) { 
		filter: invert(1) brightness(0.7); 
	}
	.map-wrapper.light :global(.maplibregl-ctrl-bottom-left .maplibregl-ctrl) { 
		filter: none; 
	}
	.map-wrapper {
		position: relative; width: 100%; max-width: 1080px; margin: 0 auto;
		height: 62vh; min-height: 460px; border: 1px solid rgba(255,255,255,0.1);
	}
	.map { width: 100%; height: 100%; }

	:global(.maplibregl-popup-content) {
		border-radius: 10px; background: transparent !important;
		padding: 0 !important; box-shadow: 0 4px 20px rgba(0,0,0,0.6) !important;
	}
	:global(.maplibregl-popup-close-button) { color: #ffffff; }
</style>
