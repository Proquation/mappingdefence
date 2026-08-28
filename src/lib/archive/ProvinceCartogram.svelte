<script>
	import { onDestroy, onMount } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import * as d3 from 'd3';

	export let rows = [];
	export let provinceGeojson = null;
	export let lqBasis = 'sales';
	export let formatSales = (v) => `${v}`;

	let map, mapContainer, mapLoaded = false, popup, markerLayer;

	// LQ diverging scale: blue (<1 under) — white (=1) — red (>1 over),
	// clamped at a high percentile so a few extreme small regions don't wash out.
	const UNDER = '#2c7fb8';
	const MID = '#f7f7f7';
	const OVER = '#d7301f';

	let centroidByUid = {};

	// Manual province label points (PRUID -> [lng, lat]), placed at populated centres
	const PROV_POINTS = {
		'10': [-53.2, 48.5],   // Newfoundland and Labrador
		'11': [-63.2, 46.4],   // Prince Edward Island
		'12': [-63.0, 45.0],   // Nova Scotia
		'13': [-66.5, 46.5],   // New Brunswick
		'24': [-71.5, 47.0],   // Quebec
		'35': [-80.0, 44.5],   // Ontario
		'46': [-98.5, 51.5],   // Manitoba
		'47': [-106.0, 52.0],  // Saskatchewan
		'48': [-114.0, 52.5],  // Alberta
		'59': [-123.0, 52.0],  // British Columbia
		'60': [-135.0, 63.0],  // Yukon
		'61': [-119.0, 64.0],  // Northwest Territories
		'62': [-90.0, 64.0]    // Nunavut
	};

	function computeCentroids() {
		// Use hardcoded province points keyed by PRUID (region_uid)
		centroidByUid = { ...PROV_POINTS };
	}

	// function polygonCentroid(geom) {
	// 	let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
	// 	const walk = (coords) => {
	// 		if (typeof coords[0] === 'number') {
	// 			minX = Math.min(minX, coords[0]); maxX = Math.max(maxX, coords[0]);
	// 			minY = Math.min(minY, coords[1]); maxY = Math.max(maxY, coords[1]);
	// 		} else coords.forEach(walk);
	// 	};
	// 	walk(geom.coordinates);
	// 	if (!isFinite(minX)) return [-95, 60];
	// 	return [(minX + maxX) / 2, (minY + maxY) / 2];
	// }

	$: lqField = { sales: 'lq_sales', firms: 'lq_firms', jobs: 'lq_jobs' }[lqBasis];

	// Build bubble data: join rows to centroids, compute radii + colors
	$: bubbles = (() => {
		if (!mapLoaded || !rows.length) return [];
		const withGeo = rows
			.filter((r) => centroidByUid[r.region_uid])
			.map((r) => {
				const firms = (r.suppressed === true || r.suppressed === 'True') ? 0 : Number(r.n_firms) || 0;
				const sales = Number.isFinite(r.total_sales_M) ? r.total_sales_M : 0;
				const jobs = Number.isFinite(r.total_jobs) ? r.total_jobs : 0;
				return {
					uid: r.region_uid,
					name: r.region_name,
					sales,
					lq: Number.isFinite(r[lqField]) ? r[lqField] : null,
					n_firms: r.n_firms,
					total_jobs: r.total_jobs,
					avg_employees: r.avg_employees,
					suppressed: r.suppressed === true || r.suppressed === 'True',
					lngLat: centroidByUid[r.region_uid],
					sizeVal: lqBasis === 'jobs' ? jobs : lqBasis === 'firms' ? firms : sales
				};
			})
		console.log(lqField, rows[0]?.lq_sales, rows[0]?.[lqField]);
		return withGeo;
	})();

	$: totalMetric = (() => {
		if (lqBasis === 'sales') return bubbles.map((b) => b.sales).filter(Number.isFinite).reduce((s, v) => s + v, 0);
		if (lqBasis === 'jobs')  return bubbles.map((b) => b.total_jobs).filter(Number.isFinite).reduce((s, v) => s + v, 0);
		// firms — n_firms is a string ("<2" when suppressed); coerce, skip suppressed
		return bubbles.filter((b) => !b.suppressed).map((b) => Number(b.n_firms) || 0).reduce((s, v) => s + v, 0);
	})();

	$: totalLabel = lqBasis === 'sales' ? 'Total sales (shown)'
				: lqBasis === 'jobs'  ? 'Total jobs (shown)'
				: 'Total firms (shown)';

	$: totalDisplay = lqBasis === 'sales' ? formatSales(totalMetric)
					: totalMetric.toLocaleString();

	$: maxSize = bubbles.length ? Math.max(...bubbles.map((b) => b.sizeVal), 1) : 1;
	// Clamp LQ color at the 95th percentile of present values
	$: lqClamp = (() => {
		const vals = bubbles.map((b) => b.lq).filter((v) => Number.isFinite(v)).sort((a, b) => a - b);
		if (!vals.length) return 3;
		const p95 = vals[Math.floor(vals.length * 0.95)] ?? vals[vals.length - 1];
		return Math.max(2, p95);
	})();

	function radiusPx(v) {
		const t = Math.sqrt(v / maxSize);
		return 6 + t * 34;
	}

	function lqColor(lq) {
		if (lq == null) return '#cfcfcf';
		// map [1/lqClamp .. 1 .. lqClamp] -> diverging
		if (lq >= 1) {
			const t = Math.min(1, (lq - 1) / (lqClamp - 1));
			return d3.interpolateRgb(MID, OVER)(t);
		}
		const t = Math.min(1, (1 - lq) / (1 - 1 / lqClamp));
		return d3.interpolateRgb(MID, UNDER)(t);
	}

	function project(lngLat) {
		return map.project(lngLat);
	}
	function drawBubbles() {
		if (!mapLoaded || !markerLayer) return;
		const svg = d3.select(markerLayer);
		svg.selectAll('*').remove();
 
		const nodes = bubbles.map((b) => {
			const p = project(b.lngLat);
			return { ...b, x: p.x, y: p.y, r: radiusPx(b.sizeVal) };
		});
 
		const sim = d3.forceSimulation(nodes)
			.force('x', d3.forceX((d) => project(d.lngLat).x).strength(0.2))
			.force('y', d3.forceY((d) => project(d.lngLat).y).strength(0.2))
			.force('collide', d3.forceCollide((d) => d.r + 1).strength(0.9))
			.stop();
		for (let i = 0; i < 160; i++) sim.tick();
 
		const g = svg.append('g');
		const node = g.selectAll('g').data(nodes).join('g')
			.attr('transform', (d) => `translate(${d.x},${d.y})`)
			.style('cursor', 'pointer')
			.on('click', (event, d) => showPopup(d));
 
		node.append('circle')
			.attr('r', (d) => d.r)
			.attr('fill', (d) => lqColor(d.lq))
			.attr('stroke', '#444')
			.attr('stroke-width', 0.7)
			.attr('fill-opacity', 0.85);
 
		// Label provinces whose circle is big enough
		node.filter((d) => d.r > 22).append('text')
			.attr('text-anchor', 'middle').attr('dy', '-0.1em')
			.style('font-family', 'OpenSansBold').style('font-size', '11px')
			.style('fill', '#1a1a1a').style('pointer-events', 'none')
			.text((d) => abbrev(d.name));
 
		node.filter((d) => d.r > 22).append('text')
			.attr('text-anchor', 'middle').attr('dy', '1.1em')
			.style('font-family', 'OpenSans').style('font-size', '10px')
			.style('fill', '#1a1a1a').style('pointer-events', 'none')
			.text((d) => (d.suppressed ? '' : formatSales(d.sales)));
	}
 
	function abbrev(name) {
		const m = {
			'British Columbia': 'BC', 'Alberta': 'AB', 'Saskatchewan': 'SK', 'Manitoba': 'MB',
			'Ontario': 'ON', 'Quebec': 'QC', 'Québec': 'QC', 'New Brunswick': 'NB',
			'Nova Scotia': 'NS', 'Prince Edward Island': 'PEI', 'Newfoundland and Labrador': 'NL',
			'Yukon': 'YT', 'Northwest Territories': 'NT', 'Nunavut': 'NU'
		};
		// handle bilingual "Ontario / Ontario" or "Quebec / Québec"
		const key = Object.keys(m).find((k) => name?.includes(k));
		return key ? m[key] : name;
	}
 
	function showPopup(d) {
		if (popup) popup.remove();
		const salesTxt = d.suppressed ? 'Suppressed' : formatSales(d.sales);
		const lqTxt = d.lq == null ? 'N/A' : d.lq.toFixed(2) ;
		const empTxt = (d.avg_employees == null || d.avg_employees === '') ? 'N/A'
			: Number(d.avg_employees).toFixed(0);
		const jobsTxt = (d.total_jobs == null || d.total_jobs === '') ? 'N/A'
			: Number(d.total_jobs).toLocaleString();
		popup = new maplibregl.Popup({ closeButton: true })
			.setLngLat(d.lngLat)
			.setHTML(
				`<div style="font-family: OpenSans, sans-serif; font-size: 13px; line-height: 1.4;">
					<div style="font-weight: 600; margin-bottom: 4px;">${d.name}</div>
					<div>Sales: ${salesTxt}</div>
					<div>LQ (${lqBasis}): ${lqTxt}</div>
					<div>Firms: ${d.n_firms ?? 'N/A'}</div>
					<div>Total jobs: ${jobsTxt}</div>
					<div>Avg. employees: ${empTxt}</div>
				</div>`
			)
			.addTo(map);
	}
 
	$: if (mapLoaded && bubbles) drawBubbles();
 
	onMount(() => {
		map = new maplibregl.Map({
			container: mapContainer,
			style: 'https://tiles.openfreemap.org/styles/positron',
			center: [-95, 53], zoom: 3.2, minZoom: 2, maxZoom: 10,
			attributionControl: false,
			projection: 'globe'
		});
		map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'bottom-left');
 
		map.on('load', () => {
			if (provinceGeojson) {
				map.addSource('prov-outline', { type: 'geojson', data: provinceGeojson });
				map.addLayer({
					id: 'prov-outline', type: 'line', source: 'prov-outline',
					paint: { 'line-color': '#9aa', 'line-width': 0.5, 'line-opacity': 0.5 }
				});
			}
			const overlay = document.createElement('div');
			overlay.style.cssText = 'position:absolute;inset:0;pointer-events:none;';
			const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
			svg.style.cssText = 'width:100%;height:100%;pointer-events:none;';
			svg.addEventListener('mousedown', (e) => e.stopPropagation(), false);
			overlay.appendChild(svg);
			mapContainer.appendChild(overlay);
			markerLayer = svg;
			const mo = new MutationObserver(() => {
				svg.querySelectorAll('g').forEach((c) => (c.style.pointerEvents = 'auto'));
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
		});
	});
 
	onDestroy(() => { if (popup) popup.remove(); if (map) map.remove(); map = null; });
</script>
 
<div class="map-wrapper">
	<div class="map" bind:this={mapContainer}></div>
	<div class="total-overlay">
		<div class="total-label">{totalLabel}</div>
		<div class="total-value">{totalDisplay}</div>
	</div>
	<div class="legend">
		<div class="legend-title">Bubble size = total {lqBasis === 'firms' ? 'firms' : lqBasis === 'jobs' ? 'jobs' : 'sales'}</div>
		<div class="legend-title">Colour = location quotient ({lqBasis})</div>
		<div class="lq-ramp">
			<span>under</span>
			<span class="ramp" style="background: linear-gradient(to right, {UNDER}, {MID}, {OVER});"></span>
			<span>over</span>
		</div>
		<div class="lq-mid">1.0× = national average</div>
	</div>
</div>
 
<style>
	.total-overlay {
		position: absolute; top: 12px; left: 12px;
		background: rgba(255,255,255,0.92); border: 1px solid var(--brandGray);
		border-radius: 6px; padding: 8px 12px; font-family: OpenSans;
		box-shadow: 0 2px 8px rgba(0,0,0,0.12); z-index: 1; pointer-events: none;
	}
	.total-label { font-size: 11px; color: var(--brandGray70); font-family: OpenSansBold; margin-bottom: 2px; }
	.total-value { font-size: 20px; font-family: TradeGothicBold; color: var(--brandDarkBlue); }
	
	.map-wrapper {
		position: relative; width: 100%; max-width: 1080px; margin: 0 auto;
		height: 62vh; min-height: 460px; border: 1px solid var(--brandGray);
	}
	.map { width: 100%; height: 100%; }
	.legend {
		position: absolute; top: 12px; right: 12px;
		background: rgba(255,255,255,0.92); border: 1px solid var(--brandGray);
		border-radius: 6px; padding: 8px 12px; font-family: OpenSans; font-size: 12px;
		box-shadow: 0 2px 8px rgba(0,0,0,0.12);
	}
	.legend-title { font-family: OpenSansBold; color: var(--brandGray90); margin-bottom: 2px; }
	.lq-ramp { display: flex; align-items: center; gap: 6px; margin-top: 6px; }
	.ramp { display: inline-block; width: 120px; height: 10px; border-radius: 2px; border: 1px solid var(--brandGray); }
	.lq-mid { color: var(--brandGray70); margin-top: 2px; }
	:global(.maplibregl-popup-content) { border-radius: 10px; }
</style>
