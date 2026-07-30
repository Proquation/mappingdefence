<script>
	import { onDestroy, onMount } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import * as d3 from 'd3';
	import { base } from '$app/paths';

	export let rows = [];
	export let cmaGeojson = null;
	export let provinceGeojson = null;
	export let metric = 'value'; // 'value' | 'count' | 'vendors'
	export let formatValue = (v) => `${v}`;
	export let usGeojson = null;
	export let darkMode = true;
	export let militaryGeojson = null;
	export let showMilitaryBases = false;

	let map, mapContainer, mapLoaded = false, popup, markerLayer;

	// Sequential ramp only — no LQ / diverging scale for contracts
	const SEQ_LO = '#a8d4f5', SEQ_HI = '#4db8ff';

	const MIL_ICONS = {
		'Canadian Army': `${base}/img/Badge_of_the_Canadian_Army.svg`,
		'Royal Canadian Airforce': `${base}/img/Badge_of_the_RCAF.svg`,
		'Royal Canadian Navy': `${base}/img/Badge_of_the_Royal_Canadian_Navy.svg`,
		'All Services': `${base}/img/Badge_of_the_Canadian_Armed_Forces.png`
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

	function normalizeRegionUid(id) {
		const s = String(id).trim();
		return /^\d+$/.test(s) ? s.padStart(3, '0') : s;
	}


	function computeCentroids() {
		console.log('>>> computeCentroids: START, features =', cmaGeojson?.features?.length);
		console.time('computeCentroids');
		const c = {};
		if (cmaGeojson) {
			for (const f of cmaGeojson.features) {
				
				const uid = normalizeRegionUid(f.properties.region_uid);
				c[uid] = polygonCentroid(f.geometry);
			}
		}
		centroidByUid = c;
		console.timeEnd('computeCentroids');
		console.log('<<< computeCentroids: DONE,', Object.keys(c).length, 'regions');
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

	let centroidsComputedFor = null;

	$: if (mapLoaded && cmaGeojson && cmaGeojson !== centroidsComputedFor) {
		computeCentroids();
		centroidsComputedFor = cmaGeojson;
	}

	// ---- Build bubbles directly from contracts_cma_agg.csv rows ----
	// Expected row shape: { region_uid, region_name, year, tier, object_cluster,
	//                        total_value, n_contracts, n_vendors }
	$: bubbles = (() => {
		if (!mapLoaded || !rows.length) return [];
		return rows
			.filter((r) => centroidByUid[r.region_uid])
			.map((r) => {
				const value    = Number.isFinite(r.total_value)  ? r.total_value  : 0;
				const count    = Number.isFinite(r.n_contracts)  ? r.n_contracts  : 0;
				const vendors  = Number.isFinite(r.n_vendors)    ? r.n_vendors    : 0;
				const metricVal = metric === 'count' ? count : metric === 'vendors' ? vendors : value;
				return {
					uid: r.region_uid,
					name: r.region_name,
					value, count, vendors,
					lngLat: centroidByUid[r.region_uid],
					colorVal: metricVal,
					sizeVal: metricVal
				};
			});
	})();

	

	function colorFor(b) {
		if (!(b.colorVal > 0)) return noDataColor;
		const t = Math.min(1, b.colorVal / Math.max(1, effectiveClamp));
		return d3.interpolateRgb(SEQ_LO, SEQ_HI)(t);
	}

	// Contracts have no "rural" concept the way company LQ data does, but
	// keep the same RURAL_-prefix convention in case non-CMA buckets are
	// ever added back to contracts_cma_agg.csv later.
	$: cmaBubbles = bubbles.filter(b => !String(b.uid).startsWith('RURAL_'));
	$: ruralBubbles = bubbles.filter(b => String(b.uid).startsWith('RURAL_'));

	$: totalMetric = (() => {
		if (metric === 'count')   return cmaBubbles.map(b => b.count).reduce((s, v) => s + v, 0);
		if (metric === 'vendors') return cmaBubbles.map(b => b.vendors).reduce((s, v) => s + v, 0);
		return cmaBubbles.map(b => b.value).reduce((s, v) => s + v, 0);
	})();

	$: totalLabel = metric === 'count' ? 'Total contracts (shown)'
		: metric === 'vendors' ? 'Total vendors (shown)'
		: 'Total contract value (shown)';
	$: totalDisplay = metric === 'value' ? formatValue(totalMetric) : totalMetric.toLocaleString();


	export let sizeBins = null; // { thresholds: number[], radii: number[] } from parent, fixed across years for current filter

	const DEFAULT_BINS = { thresholds: [1], radii: [3, 25] };
	$: effectiveBins = sizeBins && sizeBins.thresholds?.length ? sizeBins : DEFAULT_BINS;
	$: effectiveClamp = effectiveBins.thresholds[effectiveBins.thresholds.length - 1]; // used only for color gradient normalization

	function radiusForValue(v) {
		const { thresholds, radii } = effectiveBins;
		for (let i = 0; i < thresholds.length; i++) {
			if (v < thresholds[i]) return radii[i];
		}
		return radii[radii.length - 1];
	}

	$: sizeLegendSteps = (() => {
		const { thresholds, radii } = effectiveBins;
		return radii.map((rBase, i) => {
			const r = Math.min(Math.max(3, rBase * currentZoomScale), MAX_LEGEND_R);
			let label;
			if (i === 0) label = `< ${formatSizeVal(thresholds[0])}`;
			else if (i === radii.length - 1) label = `${formatSizeVal(thresholds[i - 1])}+`;
			else label = `${formatSizeVal(thresholds[i - 1])}–${formatSizeVal(thresholds[i])}`;
			return { r, label };
		});
	})();

	function formatSizeVal(v) {
		if (metric === 'value') return formatValue(v);
		return Math.round(v).toLocaleString();
	}

	const MAX_LEGEND_R = 40;


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
		const ICON_SIZE = 20;
		const milNodes = militaryGeojson.features.map(f => {
			const p = map.project(f.geometry.coordinates);
			return { x: p.x, y: p.y, name: f.properties.Name, type: f.properties.Type };
		});

		g.selectAll('image.mil-marker')
			.data(milNodes)
			.join('image')
			.attr('class', 'mil-marker')
			.attr('href', d => MIL_ICONS[d.type] || MIL_ICONS['All Services'])
			.attr('x', d => d.x - ICON_SIZE / 2)
			.attr('y', d => d.y - ICON_SIZE / 2)
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
		console.log('>>> drawBubbles: START, mapLoaded=', mapLoaded, 'markerLayer=', !!markerLayer, 'bubbles=', bubbles.length);
		if (!mapLoaded || !markerLayer) {
			console.log('<<< drawBubbles: BAILED (not ready)');
			return;
		}
		console.time('drawBubbles');
		const zoom = map.getZoom();
		const zoomScale = Math.max(0.1, (zoom - 2) / 2);
		const labelMinR = zoom < 2 ? 999 : zoom < 4 ? 18 : zoom < 5.5 ? 12 : 8;
		const svg = d3.select(markerLayer);
		currentZoomScale = zoomScale;
		svg.selectAll('*').remove();

		console.time('drawBubbles: build nodes');
		const allNodes = cmaBubbles.map((b) => {
			const p = project(b.lngLat);
			const baseR = radiusForValue(b.sizeVal); // was radiusPx(b.sizeVal)
			return { ...b, x: p.x, y: p.y, r: Math.max(3, baseR * zoomScale) };
		});
		console.timeEnd('drawBubbles: build nodes');
		console.log('nodes built:', allNodes.length);

		console.time('drawBubbles: d3 render');
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
		console.timeEnd('drawBubbles: d3 render');

		console.time('drawBubbles: military points');
		drawMilitaryPoints(g);
		console.timeEnd('drawBubbles: military points');

		console.timeEnd('drawBubbles');
		console.log('<<< drawBubbles: DONE');
	}

	function showPopup(d) {
		if (popup) popup.remove();
		const rowsHtml = `
			<div>Total value: ${formatValue(d.value)}</div>
			<div>Contracts: ${d.count.toLocaleString()}</div>
			<div>Vendors: ${d.vendors.toLocaleString()}</div>`;

		const popupLngLat = map.unproject([d.x, d.y]);
		popup = new maplibregl.Popup({ closeButton: false, closeOnClick: true })
			.setLngLat(popupLngLat)
			.setHTML(`<div style="font-family:OpenSans,sans-serif;font-size:13px;line-height:1.6;background:#1e2433;color:#e0e0e0;padding:10px;border-radius:8px;">
				<div style="font-weight:600;margin-bottom:4px;color:#ffffff;">${d.name}</div>
				${rowsHtml}
			</div>`)
			.addTo(map);
	}

	$: if (mapLoaded && (bubbles || metric || darkMode || showMilitaryBases || militaryGeojson)) drawBubbles();

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
				const zoomDelta = -e.deltaY * 0.005;
				map.zoomTo(map.getZoom() + zoomDelta, { around: map.unproject(point) });
			}, { passive: false });

			const mo = new MutationObserver(() => {
				svg.querySelectorAll('circle, image').forEach((c) => (c.style.pointerEvents = 'auto'));
			});
			mo.observe(svg, { childList: true, subtree: true });

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
			Bubble size — {metric}
		</div>
		<div class="size-legend-items">
			{#each sizeLegendSteps as step}
				<div class="size-legend-item">
					<svg width={step.r * 2 + 4} height={step.r * 2 + 4}>
						<circle cx={step.r + 2} cy={step.r + 2} r={step.r} fill="none"
							stroke={darkMode ? 'rgba(255,255,255,0.5)' : 'rgba(0,0,0,0.4)'} stroke-width="1" />
					</svg>
					<span style="color:{darkMode ? 'rgba(255,255,255,0.85)' : 'rgba(0,0,0,0.75)'};">{step.label}</span>
				</div>
			{/each}
		</div>
	</div>
</div>

<div class="legend-bar">
	<div class="legend-inner">
		<div class="legend-title">
			{metric === 'value' ? 'Total contract value' : metric === 'count' ? 'Number of contracts' : 'Number of vendors'}
		</div>
		<div class="ramp-wrap">
			<div class="ramp" style="background: linear-gradient(to right, {SEQ_LO} 0%, {SEQ_HI} 100%)"></div>
			<div class="ticks">
				<span style="left:0%">0</span>
				<span style="left:100%">{metric === 'value' ? formatValue(effectiveClamp) : Math.round(effectiveClamp).toLocaleString()}+</span>
			</div>
		</div>
	</div>
</div>

{#if showMilitaryBases}
<div class="legend-bar" style="margin-top: 4px;">
	<div class="legend-inner">
		<div class="legend-title">Canadian Forces Base (CFB)</div>
		<div class="mil-legend-row">
			{#each Object.entries(MIL_ICONS) as [type, icon]}
				<div class="mil-legend-item">
					<img src={icon} alt={type} class="mil-icon" />{type}
				</div>
			{/each}
		</div>
	</div>
</div>
{/if}

{#if ruralBubbles.length}
<div class="rural-table">
	<div class="rural-title">Other / non-CMA regions</div>
	<table>
		<thead>
			<tr>
				<th>Region</th>
				<th>Total value</th>
				<th>Contracts</th>
				<th>Vendors</th>
			</tr>
		</thead>
		<tbody>
			{#each ruralBubbles.sort((a,b) => b.value - a.value) as b}
			<tr>
				<td>{b.name}</td>
				<td>{formatValue(b.value)}</td>
				<td>{b.count.toLocaleString()}</td>
				<td>{b.vendors.toLocaleString()}</td>
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
	.legend-inner { width: 680px; }
	.ramp-wrap { position: relative; width: 100%; margin: 0 auto; }
	.ramp { width: 100%; height: 12px; border-radius: 2px; }
	.ticks { position: relative; height: 18px; margin-top: 2px; }
	.ticks span {
		position: absolute; transform: translateX(-50%);
		font-size: 11px; color: var(--brandWhite); white-space: nowrap;
	}
	.ticks span:first-child { transform: none; }
	.ticks span:last-child  { transform: translateX(-100%); }

	.map-wrapper :global(.maplibregl-ctrl-bottom-left .maplibregl-ctrl) {
		filter: invert(1) brightness(0.7);
	}
	.map-wrapper.light :global(.maplibregl-ctrl-bottom-left .maplibregl-ctrl) {
		filter: none;
	}
	.map { width: 100%; height: 100%; }

	:global(.maplibregl-popup-content) {
		border-radius: 10px; background: transparent !important;
		padding: 0 !important; box-shadow: 0 4px 20px rgba(0,0,0,0.6) !important;
	}
	:global(.maplibregl-popup-close-button) { color: #ffffff; }
</style>
