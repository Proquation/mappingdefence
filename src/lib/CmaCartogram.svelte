<script>
	import { onDestroy, onMount } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import * as d3 from 'd3';

	export let rows = [];
	export let cmaGeojson = null;
	export let provinceGeojson = null;
	export let lqBasis = 'sales';
	export let formatSales = (v) => `${v}`;

	let map, mapContainer, mapLoaded = false, popup;

	const UNDER = '#ff6b4a';
	const MID   = '#ffffff';
	const OVER  = '#4db8ff';

	// Minimal dark style — just a dark canvas, no tiles
	const DARK_STYLE = {
		version: 8,
		glyphs: 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
		sources: {},
		layers: [{ id: 'background', type: 'background', paint: { 'background-color': '#111827' } }]
	};

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

	// Short CMA labels for bubbles
	function shortCmaName(name) {
		if (!name) return '';
		// Strip province suffix like " - ON" or " (CMA)"
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
				return {
					uid: r.region_uid,
					name: r.region_name,
					sales, firms, jobs,
					lq: Number.isFinite(r[lqField]) ? r[lqField] : null,
					n_firms: r.n_firms,
					total_jobs: r.total_jobs,
					avg_employees: r.avg_employees,
					suppressed: r.suppressed === true || r.suppressed === 'True',
					lngLat: centroidByUid[r.region_uid],
					sizeVal: lqBasis === 'jobs' ? jobs : lqBasis === 'firms' ? firms : sales
				};
			});
	})();

	$: totalMetric = (() => {
		if (lqBasis === 'sales') return bubbles.map((b) => b.sales).filter(Number.isFinite).reduce((s, v) => s + v, 0);
		if (lqBasis === 'jobs')  return bubbles.map((b) => b.total_jobs).filter(Number.isFinite).reduce((s, v) => s + v, 0);
		return bubbles.filter((b) => !b.suppressed).map((b) => Number(b.n_firms) || 0).reduce((s, v) => s + v, 0);
	})();

	$: totalLabel   = lqBasis === 'sales' ? 'Total sales (shown)' : lqBasis === 'jobs' ? 'Total jobs (shown)' : 'Total firms (shown)';
	$: totalDisplay = lqBasis === 'sales' ? formatSales(totalMetric) : totalMetric.toLocaleString();

	$: maxSales = bubbles.length ? Math.max(...bubbles.map((b) => b.sizeVal), 1) : 1;
	$: lqClamp = (() => {
		const vals = bubbles.map((b) => b.lq).filter((v) => Number.isFinite(v)).sort((a, b) => a - b);
		if (!vals.length) return 3;
		return Math.max(2, vals[Math.floor(vals.length * 0.95)] ?? vals[vals.length - 1]);
	})();

	function radiusPx(sales) {
		const t = Math.sqrt(sales / maxSales);
		return 6 + t * 34;
	}

	function lqColor(lq) {
		if (lq == null) return '#3a3a4a';
		if (lq >= 1) {
			const t = Math.min(1, (lq - 1) / (lqClamp - 1));
			return d3.interpolateRgb(MID, OVER)(t);
		}
		const t = Math.min(1, (1 - lq) / (1 - 1 / lqClamp));
		return d3.interpolateRgb(MID, UNDER)(t);
	}

	function project(lngLat) { return map.project(lngLat); }

	let markerLayer;

	function drawBubbles() {
		if (!mapLoaded || !markerLayer) return;
		const zoom = map.getZoom();
		const zoomScale = 1 + Math.max(0, zoom - 3.2) * 0.18;
		// Label threshold: lower zoom = only biggest bubbles labelled
		const labelMinR = zoom < 3.5 ? 30 : zoom < 4.5 ? 22 : zoom < 5.5 ? 16 : zoom < 6.5 ? 12 : 8;

		const svg = d3.select(markerLayer);
		svg.selectAll('*').remove();

		const nodes = bubbles.map((b) => {
			const p = project(b.lngLat);
			return { ...b, x: p.x, y: p.y, r: radiusPx(b.sizeVal) * zoomScale };
		});

		const sim = d3.forceSimulation(nodes)
			.force('x', d3.forceX((d) => project(d.lngLat).x).strength(0.25))
			.force('y', d3.forceY((d) => project(d.lngLat).y).strength(0.25))
			.force('collide', d3.forceCollide((d) => d.r + 1).strength(0.9))
			.stop();
		for (let i = 0; i < 120; i++) sim.tick();

		const g = svg.append('g');
		const node = g.selectAll('g').data(nodes).join('g')
			.attr('transform', (d) => `translate(${d.x},${d.y})`)
			.style('cursor', 'pointer')
			.on('click', (event, d) => showPopup(d));

		node.append('circle')
			.attr('r', (d) => d.r)
			.attr('fill', (d) => lqColor(d.lq))
			.attr('stroke', (d) => String(d.uid).startsWith('RURAL_') ? 'rgba(255,255,255,0.5)' : 'rgba(255,255,255,0.2)')
			.attr('stroke-width', (d) => String(d.uid).startsWith('RURAL_') ? 1.5 : 0.6)
			.attr('stroke-dasharray', (d) => String(d.uid).startsWith('RURAL_') ? '3,2' : 'none')
			.attr('fill-opacity', 0.85);

		// Labels — zoom-dependent
		node.filter((d) => d.r >= labelMinR)
			.append('text')
			.attr('text-anchor', 'middle')
			.attr('dy', d => d.r >= labelMinR + 6 ? '-0.15em' : '0.35em')
			.style('font-family', 'OpenSansBold')
			.style('font-size', (d) => `${Math.min(11, Math.max(8, d.r * 0.35))}px`)
			.style('fill', '#ffffff')
			.style('pointer-events', 'none')
			.text((d) => shortCmaName(d.name));

		// Second line (sales) only for larger bubbles
		node.filter((d) => d.r >= labelMinR + 6 && !d.suppressed)
			.append('text')
			.attr('text-anchor', 'middle')
			.attr('dy', '1.1em')
			.style('font-family', 'OpenSans')
			.style('font-size', '9px')
			.style('fill', 'rgba(255,255,255,0.75)')
			.style('pointer-events', 'none')
			.text((d) => formatSales(d.sales));
	}

	function showPopup(d) {
		if (popup) popup.remove();
		const salesTxt = d.suppressed ? 'Suppressed' : formatSales(d.sales);
		const lqTxt    = d.lq == null ? 'N/A' : d.lq.toFixed(2) + '×';
		const empTxt   = (d.avg_employees == null || d.avg_employees === '') ? 'N/A' : Number(d.avg_employees).toFixed(0);
		const jobsTxt  = (d.total_jobs == null || d.total_jobs === '') ? 'N/A' : Number(d.total_jobs).toLocaleString();
		const popupLngLat = map.unproject([d.x, d.y]);
		popup = new maplibregl.Popup({ closeButton: true })
			.setLngLat(popupLngLat)
			.setHTML(`
				<div style="font-family:OpenSans,sans-serif;font-size:13px;line-height:1.4;background:#1e2433;color:#e0e0e0;padding:10px;border-radius:8px;">
					<div style="font-weight:600;margin-bottom:4px;color:#ffffff;">${d.name}</div>
					<div>Sales: ${salesTxt}</div>
					<div>LQ (${lqBasis}): ${lqTxt}</div>
					<div>Firms: ${d.n_firms ?? 'N/A'}</div>
					<div>Total jobs: ${jobsTxt}</div>
					<div>Avg. employees: ${empTxt}</div>
				</div>`)
			.addTo(map);
	}

	$: if (mapLoaded && bubbles) drawBubbles();

	onMount(() => {
		map = new maplibregl.Map({
			container: mapContainer,
			style: DARK_STYLE,
			center: [-95, 53], zoom: 3.2, minZoom: 2, maxZoom: 10,
			attributionControl: false,
			projection: 'globe'
		});
		map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'bottom-left');

		map.on('load', () => {
			// Province fill + outline — the only basemap elements
			if (provinceGeojson) {
				map.addSource('prov', { type: 'geojson', data: provinceGeojson });
				map.addLayer({
					id: 'prov-fill', type: 'fill', source: 'prov',
					paint: { 'fill-color': '#1a2235', 'fill-opacity': 1 }
				});
				map.addLayer({
					id: 'prov-line', type: 'line', source: 'prov',
					paint: { 'line-color': '#3a4a6a', 'line-width': 0.8, 'line-opacity': 0.9 }
				});
			}

			// SVG overlay
			const overlay = document.createElement('div');
			overlay.style.cssText = 'position:absolute;inset:0;pointer-events:none;';
			const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
			svg.style.cssText = 'width:100%;height:100%;pointer-events:none;';
			svg.addEventListener('mousedown', (e) => e.stopPropagation(), false);
			overlay.appendChild(svg);
			mapContainer.appendChild(overlay);
			markerLayer = svg;
			const mo = new MutationObserver(() => {
				svg.querySelectorAll('circle').forEach((c) => (c.style.pointerEvents = 'auto'));
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
		<div class="rural-note">
			<svg width="16" height="16"><circle cx="8" cy="8" r="6" fill="none" stroke="rgba(255,255,255,0.5)" stroke-width="1.5" stroke-dasharray="3,2"/></svg>
			<span>Rural (province minus CMAs)</span>
		</div>
	</div>
</div>

<style>
	.total-overlay {
		position: absolute; top: 12px; left: 12px;
		background: rgba(17,24,39,0.92); border: 1px solid rgba(255,255,255,0.15);
		border-radius: 6px; padding: 8px 12px; font-family: OpenSans;
		box-shadow: 0 2px 8px rgba(0,0,0,0.4); z-index: 1; pointer-events: none;
	}
	.total-label { font-size: 11px; color: rgba(255,255,255,0.6); font-family: OpenSansBold; margin-bottom: 2px; }
	.total-value { font-size: 20px; font-family: TradeGothicBold; color: #ffffff; }

	.rural-note {
		display: flex; align-items: center; gap: 6px;
		margin-top: 6px; color: rgba(255,255,255,0.6);
	}

	.map-wrapper {
		position: relative; width: 100%; max-width: 1080px; margin: 0 auto;
		height: 62vh; min-height: 460px; border: 1px solid rgba(255,255,255,0.1);
	}
	.map { width: 100%; height: 100%; }

	.legend {
		position: absolute; top: 12px; right: 12px;
		background: rgba(17,24,39,0.92); border: 1px solid rgba(255,255,255,0.15);
		border-radius: 6px; padding: 8px 12px; font-family: OpenSans; font-size: 12px;
		box-shadow: 0 2px 8px rgba(0,0,0,0.4); color: rgba(255,255,255,0.85);
	}
	.legend-title { font-family: OpenSansBold; color: #ffffff; margin-bottom: 2px; }
	.lq-ramp { display: flex; align-items: center; gap: 6px; margin-top: 6px; }
	.ramp { display: inline-block; width: 120px; height: 10px; border-radius: 2px; border: 1px solid rgba(255,255,255,0.2); }
	.lq-mid { color: rgba(255,255,255,0.5); margin-top: 2px; }

	:global(.maplibregl-popup-content) {
		border-radius: 10px; background: transparent !important;
		padding: 0 !important; box-shadow: 0 4px 20px rgba(0,0,0,0.6) !important;
	}
	:global(.maplibregl-popup-close-button) { color: #ffffff; }
	:global(.maplibregl-ctrl-bottom-left .maplibregl-ctrl) { filter: invert(1) brightness(0.7); }
</style>
