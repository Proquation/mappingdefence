<script>
	import { onDestroy, onMount } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import * as d3 from 'd3';
	import { base } from '$app/paths';

	export let rows = [];
	export let provinceGeojson = null;
	export let metric = 'value'; // 'value' | 'count' | 'vendors'
	export let formatValue = (v) => `${v}`;
	export let usGeojson = null;
	export let darkMode = true;
	export let militaryGeojson = null;
	export let showMilitaryBases = false;

	let map, mapContainer, mapLoaded = false, popup, markerLayer;

	const SEQ_LO = '#1a2a4a', SEQ_HI = '#4db8ff';

	const MIL_ICONS = {
		'Canadian Army': `${base}/img/Badge_of_the_Canadian_Army.svg`,
		'Royal Canadian Airforce': `${base}/img/Badge_of_the_RCAF.svg`,
		'Royal Canadian Navy': `${base}/img/Badge_of_the_Royal_Canadian_Navy.svg`,
		'All Services': `${base}/img/Badge_of_the_Canadian_Armed_Forces.png`
	};

	let centroidByUid = {};

	const PROV_POINTS = {
		'10': [-60.0, 53.0],
		'11': [-63.2, 46.3],
		'12': [-63.0, 45.0],
		'13': [-66.5, 46.5],
		'24': [-72.0, 52.0],
		'35': [-84.5, 49.5],
		'46': [-98.5, 55.0],
		'47': [-106.5, 54.5],
		'48': [-114.5, 55.5],
		'59': [-124.5, 54.5],
		'60': [-135.0, 63.0],
		'61': [-120.0, 64.5],
		'62': [-94.0, 66.0]
	};
	function computeCentroids() { centroidByUid = { ...PROV_POINTS }; }

	$: mapBg    = darkMode ? '#333333' : '#e8e8e8';
	$: provFill = darkMode ? '#1a1a1a' : '#F2F2F2';
	$: provLine = darkMode ? '#333333' : '#b0b0b0';
	$: usFill   = darkMode ? '#222222' : '#F2F2F2';
	$: usLine   = darkMode ? '#2a2a2a' : '#a8a8a8';
	$: noDataColor = darkMode ? '#666666' : '#666666';
	$: labelColor  = darkMode ? '#ffffff' : '#111111';
	$: labelShadow = darkMode ? '0 1px 3px rgba(0,0,0,0.8), 0 0 6px rgba(0,0,0,0.6)' : '0 1px 2px rgba(255,255,255,0.8)';

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
		if (map.getSource('us')) { map.getSource('us').setData(usGeojson); return; }
		const beforeLayer = map.getLayer('prov-fill') ? 'prov-fill' : undefined;
		map.addSource('us', { type: 'geojson', data: usGeojson });
		map.addLayer({ id: 'us-fill', type: 'fill', source: 'us',
			paint: { 'fill-color': usFill, 'fill-opacity': 1 } }, beforeLayer);
		map.addLayer({ id: 'us-line', type: 'line', source: 'us',
			paint: { 'line-color': usLine, 'line-width': 0.5 } }, beforeLayer);
	}

	function addProvinceLayer() {
		if (!map) return;
		if (map.getSource('prov')) { map.getSource('prov').setData(provinceGeojson); return; }
		map.addSource('prov', { type: 'geojson', data: provinceGeojson });
		map.addLayer({ id: 'prov-fill', type: 'fill', source: 'prov',
			paint: { 'fill-color': provFill, 'fill-opacity': 1 } });
		map.addLayer({ id: 'prov-line', type: 'line', source: 'prov',
			paint: { 'line-color': provLine, 'line-width': 0.8, 'line-opacity': 0.9 } });
		drawBubbles();
	}

	function abbrev(name) {
		const m = {
			'British Columbia': 'BC', 'Alberta': 'AB', 'Saskatchewan': 'SK', 'Manitoba': 'MB',
			'Ontario': 'ON', 'Quebec': 'QC', 'Québec': 'QC', 'New Brunswick': 'NB',
			'Nova Scotia': 'NS', 'Prince Edward Island': 'PEI', 'Newfoundland and Labrador': 'NL',
			'Yukon': 'YT', 'Northwest Territories': 'NT', 'Nunavut': 'NU'
		};
		const key = Object.keys(m).find(k => name?.includes(k));
		return key ? m[key] : name;
	}

	// ---- Build bubbles directly from contracts_prov_agg.csv rows ----
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
		const t = Math.min(1, b.colorVal / Math.max(1, absClamp));
		return d3.interpolateRgb(SEQ_LO, SEQ_HI)(t);
	}

	$: totalMetric = (() => {
		if (metric === 'count')   return bubbles.map(b => b.count).reduce((s, v) => s + v, 0);
		if (metric === 'vendors') return bubbles.map(b => b.vendors).reduce((s, v) => s + v, 0);
		return bubbles.map(b => b.value).reduce((s, v) => s + v, 0);
	})();

	$: totalLabel = metric === 'count' ? 'Total contracts (shown)'
		: metric === 'vendors' ? 'Total vendors (shown)'
		: 'Total contract value (shown)';
	$: totalDisplay = metric === 'value' ? formatValue(totalMetric) : totalMetric.toLocaleString();

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
		return 10 + t * 42;
	}

	function formatSizeVal(v) {
		if (metric === 'value') return formatValue(v);
		return Math.round(v).toLocaleString();
	}

	$: sizeLegendSteps = (() => {
		if (!sizeClamp) return [];
		const steps = [0.25, 0.6, 1];
		return steps.map(t => {
			const val = sizeClamp * t;
			return { val, r: radiusPx(val) };
		});
	})();

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

	function drawBubbles() {
		if (!mapLoaded || !markerLayer) return;
		const svg = d3.select(markerLayer);
		svg.selectAll('*').remove();

		const nodes = bubbles.map(b => {
			const p = map.project(b.lngLat);
			return { ...b, x: p.x, y: p.y, r: radiusPx(b.sizeVal) };
		});

		const sim = d3.forceSimulation(nodes)
			.force('x', d3.forceX(d => map.project(d.lngLat).x).strength(0.2))
			.force('y', d3.forceY(d => map.project(d.lngLat).y).strength(0.2))
			.force('collide', d3.forceCollide(d => d.r + 1).strength(0.9))
			.stop();
		for (let i = 0; i < 160; i++) sim.tick();

		const g = svg.append('g');
		const node = g.selectAll('g').data(nodes).join('g')
			.attr('transform', d => `translate(${d.x},${d.y})`)
			.style('cursor', 'pointer')
			.on('mouseenter', (event, d) => showPopup(d))
			.on('mouseleave', () => { if (popup) { popup.remove(); popup = null; } });

		node.append('circle')
			.attr('r', d => d.r)
			.attr('fill', d => colorFor(d))
			.attr('stroke', darkMode ? 'rgba(255,255,255,0.2)' : 'rgba(0,0,0,0.15)')
			.attr('stroke-width', 0.7)
			.attr('fill-opacity', 0.85);

		node.append('text')
			.attr('text-anchor', 'middle').attr('dy', '-0.1em')
			.style('font-family', 'OpenSansBold').style('font-size', '11px')
			.style('fill', labelColor).style('pointer-events', 'none')
			.style('text-shadow', labelShadow)
			.text(d => abbrev(d.name));

		node.append('text')
			.attr('text-anchor', 'middle').attr('dy', '1.1em')
			.style('font-family', 'OpenSans').style('font-size', '10px')
			.style('fill', darkMode ? 'rgba(255,255,255,0.7)' : 'rgba(0,0,0,0.6)')
			.style('pointer-events', 'none')
			.text(d => formatValue(d.value));

		drawMilitaryPoints(g);
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
			svg.addEventListener('mousedown', e => e.stopPropagation(), false);
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
				svg.querySelectorAll('circle, image').forEach(c => c.style.pointerEvents = 'auto');
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

<div class="legend-bar">
	<div class="legend-inner">
		<div class="legend-title">
			{metric === 'value' ? 'Total contract value' : metric === 'count' ? 'Number of contracts' : 'Number of vendors'}
		</div>
		<div class="ramp-wrap">
			<div class="ramp" style="background: linear-gradient(to right, {SEQ_LO} 0%, {SEQ_HI} 100%)"></div>
			<div class="ticks">
				<span style="left:0%">0</span>
				<span style="left:100%">{metric === 'value' ? formatValue(absClamp) : Math.round(absClamp).toLocaleString()}+</span>
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
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 8px;
	}
	.size-legend-item {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 2px;
		font-size: 11px;
	}

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
