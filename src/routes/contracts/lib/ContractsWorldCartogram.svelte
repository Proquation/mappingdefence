<script>
	import { onDestroy, onMount } from 'svelte';
	import maplibregl from 'maplibre-gl';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import * as d3 from 'd3';
	import { base } from '$app/paths';

	// ----- Props -----
	export let rows = [];
	export let worldGeojson = null;
	export let metric = 'value'; // 'value' | 'count' | 'vendors'
	export let formatValue = (v) => `${v}`;
	export let darkMode = true;
	export let militaryGeojson = null;
	export let showMilitaryBases = false;

	// ----- Map state -----
	let map, mapContainer, mapLoaded = false, popup, markerLayer;

	// Colour ramp (same as CMA)
	const SEQ_LO = '#1a2a4a', SEQ_HI = '#4db8ff';

	// Military icons (reuse)
	const MIL_ICONS = {
		'Canadian Army': `${base}/img/Badge_of_the_Canadian_Army.svg`,
		'Royal Canadian Airforce': `${base}/img/Badge_of_the_RCAF.svg`,
		'Royal Canadian Navy': `${base}/img/Badge_of_the_Royal_Canadian_Navy.svg`,
		'All Services': `${base}/img/Badge_of_the_Canadian_Armed_Forces.png`
	};

	// ----- Centroids by country name -----
	let centroidByName = {};

	// ----- Reactive styles -----
	$: mapBg      = darkMode ? '#333333' : '#e8e8e8';
	$: countryFill = darkMode ? '#1a1a1a' : '#F2F2F2';
	$: countryLine = darkMode ? '#333333' : '#b0b0b0';
	$: noDataColor = darkMode ? '#666666' : '#666666';
	$: labelColor  = darkMode ? '#ffffff' : '#111111';
	$: labelShadow = darkMode ? '0 1px 3px rgba(0,0,0,0.8)' : '0 1px 2px rgba(255,255,255,0.8)';

	// Update map background when dark mode toggles
	$: if (mapLoaded) {
		map.setPaintProperty('background', 'background-color', mapBg);
		if (map.getLayer('country-fill')) map.setPaintProperty('country-fill', 'fill-color', countryFill);
		if (map.getLayer('country-line')) map.setPaintProperty('country-line', 'line-color', countryLine);
		drawBubbles();
	}

	// ----- Add world country layer when geojson loads -----
	$: if (mapLoaded && worldGeojson) addCountryLayer();

	function addCountryLayer() {
		if (!map) return;
		if (map.getSource('countries')) {
			map.getSource('countries').setData(worldGeojson);
			return;
		}
		map.addSource('countries', { type: 'geojson', data: worldGeojson });
		map.addLayer({
			id: 'country-fill',
			type: 'fill',
			source: 'countries',
			paint: { 'fill-color': countryFill, 'fill-opacity': 1 }
		});
		map.addLayer({
			id: 'country-line',
			type: 'line',
			source: 'countries',
			paint: { 'line-color': countryLine, 'line-width': 0.5 }
		});
		// Recompute centroids (they depend on the geojson)
		computeCentroids();
		drawBubbles();
	}

	// ----- Compute centroids from world countries -----
	function computeCentroids() {
		console.log('>>> computeCentroids (world): features =', worldGeojson?.features?.length);
		console.time('computeCentroidsWorld');
		const c = {};
		if (worldGeojson) {
			for (const f of worldGeojson.features) {
				// Try to extract country name from properties (common fields)
				const name =
					f.properties?.NAME ||
					f.properties?.ADMIN ||
					f.properties?.name ||
					f.properties?.country ||
					f.properties?.CNTRY_NAME ||
					f.properties?.SOVEREIGNT ||
					f.properties?.Country;
				if (name) {
					// Normalise name: trim and collapse spaces
					const clean = name.trim().replace(/\s+/g, ' ');
					c[clean] = polygonCentroid(f.geometry);
				}
			}
		}
		centroidByName = c;
		console.timeEnd('computeCentroidsWorld');
		console.log('<<< computeCentroidsWorld: DONE,', Object.keys(c).length, 'countries');
	}

	function polygonCentroid(geom) {
		let x = 0, y = 0, n = 0;
		const walk = (coords) => {
			if (typeof coords[0] === 'number') { x += coords[0]; y += coords[1]; n++; }
			else coords.forEach(walk);
		};
		walk(geom.coordinates);
		return n ? [x / n, y / n] : [0, 0];
	}

	// ----- Build bubbles from rows -----
	// Rows have: region_uid (like "COUNTRY_CANADA"), region_name (like "Canada"), year, tier, object_cluster,
	// total_value, n_contracts, n_vendors
	$: bubbles = (() => {
		if (!mapLoaded || !rows.length) return [];
		return rows
			.filter((r) => centroidByName[r.region_name]) // match by country name
			.map((r) => {
				const value   = Number.isFinite(r.total_value)  ? r.total_value  : 0;
				const count   = Number.isFinite(r.n_contracts)  ? r.n_contracts  : 0;
				const vendors = Number.isFinite(r.n_vendors)    ? r.n_vendors    : 0;
				const metricVal = metric === 'count' ? count : metric === 'vendors' ? vendors : value;
				return {
					name: r.region_name,
					value, count, vendors,
					lngLat: centroidByName[r.region_name],
					colorVal: metricVal,
					sizeVal: metricVal
				};
			});
	})();

	// ----- Colour and size helpers -----
	function colorFor(b) {
		if (!(b.colorVal > 0)) return noDataColor;
		const t = Math.min(1, b.colorVal / Math.max(1, absClamp));
		return d3.interpolateRgb(SEQ_LO, SEQ_HI)(t);
	}

	// Total metric (for overlay)
	$: totalMetric = (() => {
		if (metric === 'count')   return bubbles.map(b => b.count).reduce((s, v) => s + v, 0);
		if (metric === 'vendors') return bubbles.map(b => b.vendors).reduce((s, v) => s + v, 0);
		return bubbles.map(b => b.value).reduce((s, v) => s + v, 0);
	})();

	$: totalLabel = metric === 'count' ? 'Total contracts (shown)'
		: metric === 'vendors' ? 'Total vendors (shown)'
		: 'Total contract value (shown)';
	$: totalDisplay = metric === 'value' ? formatValue(totalMetric) : totalMetric.toLocaleString();

	// Clamp values for colour and size (95th percentile)
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
		if (metric === 'value') return formatValue(v);
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

	// ----- Drawing military points (same as CMA, but may be off-world; it's fine) -----
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

	// ----- Draw bubbles with d3 -----
	let currentZoomScale = 1;

	function drawBubbles() {
		console.log('>>> drawBubbles (world): START, mapLoaded=', mapLoaded, 'markerLayer=', !!markerLayer, 'bubbles=', bubbles.length);
		if (!mapLoaded || !markerLayer) {
			console.log('<<< drawBubbles (world): BAILED (not ready)');
			return;
		}
		console.time('drawBubblesWorld');
		const zoom = map.getZoom();
		const zoomScale = Math.max(0.1, (zoom - 2) / 2);
		const labelMinR = zoom < 2 ? 999 : zoom < 4 ? 18 : zoom < 5.5 ? 12 : 8;
		const svg = d3.select(markerLayer);
		currentZoomScale = zoomScale;
		svg.selectAll('*').remove();

		console.time('drawBubblesWorld: build nodes');
		const allNodes = bubbles.map((b) => {
			const p = project(b.lngLat);
			const baseR = radiusPx(b.sizeVal);
			return { ...b, x: p.x, y: p.y, r: Math.max(3, baseR * zoomScale) };
		});
		console.timeEnd('drawBubblesWorld: build nodes');
		console.log('nodes built:', allNodes.length);

		console.time('drawBubblesWorld: d3 render');
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
			.text((d) => d.name);
		console.timeEnd('drawBubblesWorld: d3 render');

		console.time('drawBubblesWorld: military points');
		drawMilitaryPoints(g);
		console.timeEnd('drawBubblesWorld: military points');

		console.timeEnd('drawBubblesWorld');
		console.log('<<< drawBubblesWorld: DONE');
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

	// ----- Redraw when dependencies change -----
	$: if (mapLoaded && (bubbles || metric || darkMode || showMilitaryBases || militaryGeojson)) drawBubbles();

	// ----- Map initialisation -----
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
			center: [0, 20], zoom: 1.8, minZoom: 1, maxZoom: 8,
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

			// If worldGeojson is already loaded, compute centroids
			if (worldGeojson) computeCentroids();
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