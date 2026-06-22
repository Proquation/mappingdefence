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

	const UNDER = '#ff6b4a';
	const MID   = '#ffffff';
	const OVER  = '#4db8ff';

	let centroidByUid = {};

	const PROV_POINTS = {
		'10': [-53.2, 48.5], '11': [-63.2, 46.4], '12': [-63.0, 45.0],
		'13': [-66.5, 46.5], '24': [-71.5, 47.0], '35': [-80.0, 44.5],
		'46': [-98.5, 51.5], '47': [-106.0, 52.0], '48': [-114.0, 52.5],
		'59': [-123.0, 52.0], '60': [-135.0, 63.0], '61': [-119.0, 64.0], '62': [-90.0, 64.0]
	};

	function computeCentroids() { centroidByUid = { ...PROV_POINTS }; }

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
					uid: r.region_uid, name: r.region_name,
					sales, lq: Number.isFinite(r[lqField]) ? r[lqField] : null,
					n_firms: r.n_firms, total_jobs: r.total_jobs, avg_employees: r.avg_employees,
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

	$: maxSize = bubbles.length ? Math.max(...bubbles.map((b) => b.sizeVal), 1) : 1;
	$: lqClamp = (() => {
		const vals = bubbles.map((b) => b.lq).filter((v) => Number.isFinite(v)).sort((a, b) => a - b);
		if (!vals.length) return 3;
		return Math.max(2, vals[Math.floor(vals.length * 0.95)] ?? vals[vals.length - 1]);
	})();

	function radiusPx(v) { return 10 + Math.sqrt(v / maxSize) * 42; }   // was 6 + ...*34

	function lqColor(lq) {
		if (lq == null) return '#3a3a4a';
		if (lq >= 1) { const t = Math.min(1, (lq - 1) / (lqClamp - 1)); return d3.interpolateRgb(MID, OVER)(t); }
		const t = Math.min(1, (1 - lq) / (1 - 1 / lqClamp));
		return d3.interpolateRgb(MID, UNDER)(t);
	}

	function abbrev(name) {
		const m = {
			'British Columbia': 'BC', 'Alberta': 'AB', 'Saskatchewan': 'SK', 'Manitoba': 'MB',
			'Ontario': 'ON', 'Quebec': 'QC', 'Québec': 'QC', 'New Brunswick': 'NB',
			'Nova Scotia': 'NS', 'Prince Edward Island': 'PEI', 'Newfoundland and Labrador': 'NL',
			'Yukon': 'YT', 'Northwest Territories': 'NT', 'Nunavut': 'NU'
		};
		const key = Object.keys(m).find((k) => name?.includes(k));
		return key ? m[key] : name;
	}

	function drawBubbles() {
		if (!mapLoaded || !markerLayer) return;
		const svg = d3.select(markerLayer);
		svg.selectAll('*').remove();

		const nodes = bubbles.map((b) => {
			const p = map.project(b.lngLat);
			return { ...b, x: p.x, y: p.y, r: radiusPx(b.sizeVal) };
		});

		const sim = d3.forceSimulation(nodes)
			.force('x', d3.forceX((d) => map.project(d.lngLat).x).strength(0.2))
			.force('y', d3.forceY((d) => map.project(d.lngLat).y).strength(0.2))
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
			.attr('stroke', 'rgba(255,255,255,0.2)')
			.attr('stroke-width', 0.7)
			.attr('fill-opacity', 0.85);

		// abbrev label — always show
		node.append('text')
			.attr('text-anchor', 'middle').attr('dy', '-0.1em')
			.style('font-family', 'OpenSansBold').style('font-size', '11px')
			.style('fill', '#ffffff').style('pointer-events', 'none')
			.text((d) => abbrev(d.name));

		// sales label — always show (unless suppressed)
		node.append('text')
			.attr('text-anchor', 'middle').attr('dy', '1.1em')
			.style('font-family', 'OpenSans').style('font-size', '10px')
			.style('fill', 'rgba(255,255,255,0.7)').style('pointer-events', 'none')
			.text((d) => (d.suppressed ? '' : formatSales(d.sales)));
	}

	function showPopup(d) {
		if (popup) popup.remove();
		const salesTxt = d.suppressed ? 'Suppressed' : formatSales(d.sales);
		const lqTxt    = d.lq == null ? 'N/A' : d.lq.toFixed(2) + '×';
		const empTxt   = (d.avg_employees == null || d.avg_employees === '') ? 'N/A' : Number(d.avg_employees).toFixed(0);
		const jobsTxt  = (d.total_jobs == null || d.total_jobs === '') ? 'N/A' : Number(d.total_jobs).toLocaleString();
		popup = new maplibregl.Popup({ closeButton: true })
			.setLngLat(d.lngLat)
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
			style: 'https://tiles.openfreemap.org/styles/dark',
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
					paint: { 'line-color': 'rgba(255,255,255,0.25)', 'line-width': 0.6, 'line-opacity': 0.7 }
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

		map.on('style.load', () => { map.setProjection({ type: map.getZoom() < 7 ? 'globe' : 'mercator' }); });
		map.on('zoom', () => { map.setProjection({ type: map.getZoom() < 7 ? 'globe' : 'mercator' }); drawBubbles(); });
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
		background: rgba(17,24,39,0.92); border: 1px solid rgba(255,255,255,0.15);
		border-radius: 6px; padding: 8px 12px; font-family: OpenSans;
		box-shadow: 0 2px 8px rgba(0,0,0,0.4); z-index: 1; pointer-events: none;
	}
	.total-label { font-size: 11px; color: rgba(255,255,255,0.6); font-family: OpenSansBold; margin-bottom: 2px; }
	.total-value { font-size: 20px; font-family: TradeGothicBold; color: #ffffff; }

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
</style>
