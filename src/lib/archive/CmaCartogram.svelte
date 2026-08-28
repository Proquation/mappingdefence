<script>
	import { onDestroy, onMount } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import * as d3 from 'd3';

	// rows: cma_rural_agg rows already filtered to the active year + mode
	//   each: { region_uid, region_name, total_sales_M, n_firms, avg_employees,
	//           lq_sales, lq_firms, lq_jobs, suppressed }
	// cmaGeojson: cma_boundaries.geojson (for CMA centroids + faint outlines)
	// provinceGeojson: province_boundaries.geojson (for rural bucket centroids)
	// lqBasis: 'sales' | 'firms' | 'jobs'
	export let rows = [];
	export let cmaGeojson = null;
	export let provinceGeojson = null;
	export let lqBasis = 'sales';
	export let formatSales = (v) => `${v}`;

	let map, mapContainer, mapLoaded = false, popup;

	// LQ diverging scale: blue (<1 under) — white (=1) — red (>1 over),
	// clamped at a high percentile so a few extreme small regions don't wash out.
	const UNDER = '#2c7fb8';
	const MID = '#f7f7f7';
	const OVER = '#d7301f';

	// STATE -> rough southern population-weighted point (avoids empty-north centroid)
	const RURAL_POINTS = {
		RURAL_ON: [-80.5, 43.6], RURAL_QC: [-72.5, 46.2], RURAL_BC: [-122.0, 49.7],
		RURAL_AB: [-113.5, 51.5], RURAL_SK: [-106.0, 51.5], RURAL_MB: [-98.0, 49.9],
		RURAL_NS: [-63.0, 45.0], RURAL_NB: [-66.5, 46.3], RURAL_NL: [-55.0, 48.5],
		RURAL_PE: [-63.2, 46.3], RURAL_NT: [-115.0, 62.0], RURAL_YT: [-135.0, 62.0],
		RURAL_NU: [-92.0, 64.0]
	};

	let centroidByUid = {};

	function computeCentroids() {
		const c = {};
		if (cmaGeojson) {
			for (const f of cmaGeojson.features) {
				const uid = String(f.properties.region_uid);
				c[uid] = polygonCentroid(f.geometry);
			}
		}
		if (provinceGeojson) {
			// map province name -> RURAL_{code} by matching the rural rows we have
			// rural points are hardcoded; just use those directly
		}
		Object.assign(c, Object.fromEntries(Object.entries(RURAL_POINTS)));
		centroidByUid = c;
	}

	function polygonCentroid(geom) {
		// crude centroid: average of all coordinates (good enough for bubble seeding)
		let x = 0, y = 0, n = 0;
		const walk = (coords) => {
			if (typeof coords[0] === 'number') { x += coords[0]; y += coords[1]; n++; }
			else coords.forEach(walk);
		};
		walk(geom.coordinates);
		return n ? [x / n, y / n] : [-95, 55];
	}

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

	$: maxSales = bubbles.length ? Math.max(...bubbles.map((b) => b.sizeVal), 1) : 1;
	// Clamp LQ color at the 95th percentile of present values
	$: lqClamp = (() => {
		const vals = bubbles.map((b) => b.lq).filter((v) => Number.isFinite(v)).sort((a, b) => a - b);
		if (!vals.length) return 3;
		const p95 = vals[Math.floor(vals.length * 0.95)] ?? vals[vals.length - 1];
		return Math.max(2, p95);
	})();

	function radiusPx(sales) {
		// area-proportional, capped
		const t = Math.sqrt(sales / maxSales);
		return 6 + t * 34; // 6–40 px
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

	let markerLayer; // a single SVG overlay we redraw on move

	function drawBubbles() {
		if (!mapLoaded || !markerLayer) return;
		const svg = d3.select(markerLayer);
		svg.selectAll('*').remove();

		// Seed nodes at projected centroids, run a short Dorling collision sim
		const nodes = bubbles.map((b) => {
			const p = project(b.lngLat);
			return { ...b, x: p.x, y: p.y, r: radiusPx(b.sizeVal) };
		});

		const sim = d3.forceSimulation(nodes)
			.force('x', d3.forceX((d) => project(d.lngLat).x).strength(0.25))
			.force('y', d3.forceY((d) => project(d.lngLat).y).strength(0.25))
			.force('collide', d3.forceCollide((d) => d.r + 1).strength(0.9))
			.stop();
		for (let i = 0; i < 120; i++) sim.tick();

		const g = svg.append('g');
		g.selectAll('circle')
			.data(nodes)
			.join('circle')
			.attr('cx', (d) => d.x)
			.attr('cy', (d) => d.y)
			.attr('r', (d) => d.r)
			.attr('fill', (d) => lqColor(d.lq))
			.attr('stroke', (d) => String(d.uid).startsWith('RURAL_') ? '#222' : '#444')
			.attr('stroke-width', (d) => String(d.uid).startsWith('RURAL_') ? 2 : 0.6)
			.attr('stroke-dasharray', (d) => String(d.uid).startsWith('RURAL_') ? '3,2' : 'none')
			.attr('fill-opacity', 0.85)
			.style('cursor', 'pointer')
			.on('click', (event, d) => showPopup(d));
	}

	function showPopup(d) {
		if (popup) popup.remove();
		const salesTxt = d.suppressed ? 'Suppressed' : formatSales(d.sales);
		const lqTxt = d.lq == null ? 'N/A' : d.lq.toFixed(2) ;
		const empTxt = (d.avg_employees == null || d.avg_employees === '') ? 'N/A'
			: Number(d.avg_employees).toFixed(0);
		const jobsTxt = (d.total_jobs == null || d.total_jobs === '') ? 'N/A'
			: Number(d.total_jobs).toLocaleString();

		// set lng lat to post-collision screen coords
		const popupLngLat = d.lngLat = (d.x != null && d.y != null) ? map.unproject([d.x, d.y]): d.lngLat;
		popup = new maplibregl.Popup({ closeButton: true })
			.setLngLat(popupLngLat)
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
			center: [-95, 53], zoom: 3.2, minZoom: 2, maxZoom: 10,
			attributionControl: false,
			projection: 'globe'              // ← add
		});
		map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'bottom-left');

		map.on('load', () => {
			// Faint CMA outlines for geographic context
			if (cmaGeojson) {
				map.addSource('cma-outline', { type: 'geojson', data: cmaGeojson });
				map.addLayer({
					id: 'cma-outline', type: 'line', source: 'cma-outline',
					paint: { 'line-color': '#9aa', 'line-width': 0.4, 'line-opacity': 0.5 }
				});
			}
			// SVG overlay container for bubbles
			const overlay = document.createElement('div');
			overlay.style.cssText = 'position:absolute;inset:0;pointer-events:none;';
			const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
			svg.style.cssText = 'width:100%;height:100%;pointer-events:none;';
			// allow circle clicks while letting map pan elsewhere
			svg.addEventListener('mousedown', (e) => e.stopPropagation(), false);
			overlay.appendChild(svg);
			mapContainer.appendChild(overlay);
			markerLayer = svg;
			// re-enable pointer events only on the svg children (circles)
			svg.style.pointerEvents = 'none';
			const obs = () => { svg.querySelectorAll('circle').forEach((c) => c.style.pointerEvents = 'auto'); };
			const mo = new MutationObserver(obs);
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
			drawBubbles();   // reproject bubbles when projection flips
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
		<div class="rural-note">
			<svg width="16" height="16"><circle cx="8" cy="8" r="6" fill="none" stroke="#222" stroke-width="2" stroke-dasharray="3,2"/></svg>
			<span>Rural (province minus its metro areas)</span>
		</div>
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

	.rural-note { 
		display: flex; 
		align-items: center; 
		gap: 6px; 
		margin-top: 6px; 
		color: var(--brandGray70); 
	}

	.map-wrapper {
		position: relative;
		width: 100%;
		max-width: 1080px;
		margin: 0 auto;
		height: 62vh;
		min-height: 460px;
		border: 1px solid var(--brandGray);
	}
	.map { width: 100%; height: 100%; }
	.legend {
		position: absolute;
		top: 12px; right: 12px;
		background: rgba(255,255,255,0.92);
		border: 1px solid var(--brandGray);
		border-radius: 6px;
		padding: 8px 12px;
		font-family: OpenSans;
		font-size: 12px;
		box-shadow: 0 2px 8px rgba(0,0,0,0.12);
	}
	.legend-title { font-family: OpenSansBold; color: var(--brandGray90); margin-bottom: 2px; }
	.lq-ramp { display: flex; align-items: center; gap: 6px; margin-top: 6px; }
	.ramp { display: inline-block; width: 120px; height: 10px; border-radius: 2px; border: 1px solid var(--brandGray); }
	.lq-mid { color: var(--brandGray70); margin-top: 2px; }
	:global(.maplibregl-popup-content) { border-radius: 10px; }
</style>
