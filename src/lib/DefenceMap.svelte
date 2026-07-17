<script>
	import { onDestroy, onMount } from 'svelte';
	import 'maplibre-gl/dist/maplibre-gl.css';
	import maplibregl from 'maplibre-gl';
	import { Protocol } from 'pmtiles';
	import { base } from '$app/paths';
	import * as d3 from 'd3';

	const protocol = new Protocol();
	maplibregl.addProtocol('pmtiles', protocol.tile);

	const SOURCE_ID = 'csd';
	const SRC_LAYER = 'csd';
	const FILL_LAYER = 'csd-fill';
	let markerLayer;

	
	export let geojson = null;
	export let recordByUid = {};
	export let formatSales = (v) => `${v}`;
	export let lqBasis = 'sales';
	export let colourType = 'lq';
	export let provinceGeojson = null;
	export let usGeojson = null;
	export let darkMode = true;
	export let militaryGeojson = null;
	export let showMilitaryBases = false;

	
	const MIL_COLORS = {
		'Canadian Army': '#2ECC71',        
		'Royal Canadian Airforce': '#9B59B6', 
		'Royal Canadian Navy': '#F1C40F',   
		'All Services': '#573F3E'           
	};

	const MIL_ICONS = {
		'Canadian Army': `${base}/img/Badge_of_the_Canadian_Army.svg`,
		'Royal Canadian Airforce': `${base}/img/Badge_of_the_RCAF.svg`,
		'Royal Canadian Navy': `${base}/img/Badge_of_the_Royal_Canadian_Navy.svg`,
		'All Services': `${base}/img/Badge_of_the_Canadian_Armed_Forces.png`
	};
	const SEQ_LO = '#1a2a4a', SEQ_HI = '#4db8ff';


	let UNDER = '#ff6b4a';
	let MID   = '#CCCCCC';
	let OVER  = '#4db8ff';

	let map, mapContainer, mapLoaded = false, popup;

	$: mapBg    = darkMode ? '#333333' : '#e8e8e8';
	$: provFill = darkMode ? '#1a1a1a' : '#F2F2F2';
	$: provLine = darkMode ? '#333333' : '#b0b0b0';
	$: usFill   = darkMode ? '#222222' : '#F2F2F2';
	$: usLine   = darkMode ? '#2a2a2a' : '#a8a8a8';
	$: noDataFill = darkMode ? '#2a2a3a' : '#d8d8d8';

	$: csdLineColor = darkMode ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.15)';

	$: if (mapLoaded && map.getLayer('csd-line')) {
		map.setPaintProperty('csd-line', 'line-color', csdLineColor);
	}

	$: MAP_STYLE = {
		version: 8,
		glyphs: 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
		sources: {},
		layers: [{ id: 'background', type: 'background', paint: { 'background-color': mapBg } }]
	};

	$: if (mapLoaded) {
		map.setPaintProperty('background', 'background-color', mapBg);
		if (map.getLayer('prov-fill')) map.setPaintProperty('prov-fill', 'fill-color', provFill);
		if (map.getLayer('prov-line')) map.setPaintProperty('prov-line', 'line-color', provLine);
		if (map.getLayer('us-fill'))  map.setPaintProperty('us-fill',  'fill-color', usFill);
		if (map.getLayer('us-line'))  map.setPaintProperty('us-line',  'line-color', usLine);
		if (map.getLayer(FILL_LAYER)) map.setPaintProperty(FILL_LAYER, 'fill-color', fillColorExpression());
	}

	$: if (mapLoaded && usGeojson) addUsLayer();
	$: if (mapLoaded && provinceGeojson) addProvinceLayer();


	function addUsLayer() {
		if (!map) return;
		if (map.getSource('us')) { map.getSource('us').setData(usGeojson); return; }
		const beforeLayer = map.getLayer('prov-fill') ? 'prov-fill' : map.getLayer(FILL_LAYER) ? FILL_LAYER : undefined;
		map.addSource('us', { type: 'geojson', data: usGeojson });
		map.addLayer({ id: 'us-fill', type: 'fill', source: 'us',
			paint: { 'fill-color': usFill, 'fill-opacity': 1 } }, beforeLayer);
		map.addLayer({ id: 'us-line', type: 'line', source: 'us',
			paint: { 'line-color': usLine, 'line-width': 0.5 } }, beforeLayer);
	}

	function addProvinceLayer() {
		if (!map) return;
		if (map.getSource('prov')) { map.getSource('prov').setData(provinceGeojson); return; }
		// Insert before CSD fill so provinces sit underneath
		const beforeLayer = map.getLayer(FILL_LAYER) ? FILL_LAYER : undefined;
		map.addSource('prov', { type: 'geojson', data: provinceGeojson });
		map.addLayer({ id: 'prov-fill', type: 'fill', source: 'prov',
			paint: { 'fill-color': provFill, 'fill-opacity': 1 } }, beforeLayer);
		map.addLayer({ id: 'prov-line', type: 'line', source: 'prov',
			paint: { 'line-color': provLine, 'line-width': 0.8, 'line-opacity': 0.9 } }, beforeLayer);
	}

	$: absClamp = (() => {
		const vals = Object.values(recordByUid).map(r => r.absVal).filter(v => Number.isFinite(v)).sort((a, b) => a - b);
		if (!vals.length) return 1;
		return vals[Math.floor(vals.length * 0.95)] ?? vals[vals.length - 1];
	})();

	$: lqClamp = (() => {
		const vals = Object.values(recordByUid).map(r => r.lq).filter(v => Number.isFinite(v)).sort((a, b) => a - b);
		if (!vals.length) return 3;
		return Math.max(1, vals[Math.floor(vals.length * 0.95)] ?? vals[vals.length - 1]);
	})();

	$: totalMetric = (() => {
		const vals = Object.values(recordByUid);
		if (lqBasis === 'sales') return vals.map(r => r.sales).filter(Number.isFinite).reduce((s, v) => s + v, 0);
		if (lqBasis === 'jobs')  return vals.map(r => r.total_jobs).filter(Number.isFinite).reduce((s, v) => s + v, 0);
		return vals.map(r => Number(r.n_firms) || 0).reduce((s, v) => s + v, 0);
	})();

	$: totalLabel   = lqBasis === 'sales' ? 'Total sales (shown)' : lqBasis === 'jobs' ? 'Total jobs (shown)' : 'Total firms (shown)';
	$: totalDisplay = lqBasis === 'sales' ? formatSales(totalMetric) : totalMetric.toLocaleString();

	let hoveredUid = null;


	function fillColorExpression() {
		if (colourType === 'totals') {
			const m = Math.max(1, absClamp);
			return [
				'case',
				['==', ['feature-state', 'abs_value'], null], noDataFill,
				['interpolate', ['linear'], ['feature-state', 'abs_value'], 0, SEQ_LO, m, SEQ_HI]
			];
		}
		const c = Math.max(2, lqClamp);
		return [
			'case',
			['==', ['feature-state', 'lq_value'], null], noDataFill,
			['interpolate', ['linear'], ['feature-state', 'lq_value'], 1/c, UNDER, 1, MID, c, OVER]
		];
	}

	function applyData() {
		if (!mapLoaded) return;
		map.removeFeatureState({ source: SOURCE_ID, sourceLayer: SRC_LAYER });
		for (const [uid, rec] of Object.entries(recordByUid)) {
			map.setFeatureState(
				{ source: SOURCE_ID, sourceLayer: SRC_LAYER, id: uid },
				{
					lq_value:  Number.isFinite(rec.lq)     ? rec.lq     : null,
					abs_value: Number.isFinite(rec.absVal) ? rec.absVal : null,
					sales_value: Number.isFinite(rec.sales) ? rec.sales : null,
					n_firms: rec.n_firms ?? null,
					total_jobs: Number.isFinite(rec.total_jobs) ? rec.total_jobs : null,
					avg_employees: Number.isFinite(rec.avg_employees) ? rec.avg_employees : null
				}
			);
		}
		if (map.getLayer(FILL_LAYER)) map.setPaintProperty(FILL_LAYER, 'fill-color', fillColorExpression());
	}

	function drawMilitaryPoints() {
		if (!map || !markerLayer) return;
		const d3svg = d3.select(markerLayer);
		d3svg.selectAll('*').remove();
		if (!showMilitaryBases || !militaryGeojson) return;

		const ICON_SIZE = 20;
		const milNodes = militaryGeojson.features.map(f => {
			const p = map.project(f.geometry.coordinates);
			return { x: p.x, y: p.y, name: f.properties.Name, type: f.properties.Type };
		});

		d3svg.selectAll('image.mil-marker')
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

	$: if (mapLoaded && (militaryGeojson || showMilitaryBases)) drawMilitaryPoints();


	onMount(() => {
		map = new maplibregl.Map({
			container: mapContainer,
			style: MAP_STYLE,
			center: [-95, 53], zoom: 3.2, minZoom: 2, maxZoom: 12,
			attributionControl: false,
			projection: 'globe'
		});
		map.addControl(new maplibregl.NavigationControl({ showCompass: true, showZoom: true }), 'bottom-left');

		map.on('load', () => {
			map.addSource(SOURCE_ID, {
				type: 'vector',
				url: `pmtiles://${base}/pmtiles/csd.pmtiles`,
				promoteId: 'region_uid'
			});
			map.addLayer({
				id: FILL_LAYER, type: 'fill', source: SOURCE_ID, 'source-layer': SRC_LAYER,
				paint: { 'fill-color': fillColorExpression(), 'fill-opacity': 0.85 }
			});
			map.addLayer({
				id: 'csd-line', type: 'line', source: SOURCE_ID, 'source-layer': SRC_LAYER,
				paint: { 'line-color': csdLineColor, 'line-width': 0.3 }
			});

			const overlay = document.createElement('div');
			overlay.style.cssText = 'position:absolute;inset:0;pointer-events:none;';
			const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
			svg.style.cssText = 'width:100%;height:100%;pointer-events:none;';
			overlay.appendChild(svg);
			mapContainer.appendChild(overlay);
			markerLayer = svg;
			const mo = new MutationObserver(() => {
				svg.querySelectorAll('image').forEach(c => c.style.pointerEvents = 'auto');
			});
			mo.observe(svg, { childList: true, subtree: true });

			drawMilitaryPoints();
			map.on('move', drawMilitaryPoints);


			mapLoaded = true;
			applyData();
			map.on('mousemove', FILL_LAYER, (event) => {
				if (!event.features?.length) return;
				const uid = String(event.features[0].properties.region_uid);
				if (uid === hoveredUid) return; // same feature, do nothing
				hoveredUid = uid;


				map.getCanvas().style.cursor = 'pointer';
				const p = event.features[0].properties;
				const name = p.region_name;
				const rec = recordByUid[uid] || {};

				function firmsTxt(n) {
					if (n === '0' || n == null) return 'No firms';
					if (n === '<2') return '1 firm (suppressed)';
					return `${Number(n).toLocaleString()} firms`;
				}
				const noData = (rec.n_firms === '0' || rec.n_firms == null);
				const lqTxt = noData ? 'No data' : Number.isFinite(rec.lq) ? rec.lq.toFixed(2) + '×' : 'Suppressed';

				let rows;
				if (lqBasis === 'firms') {
					rows = `<div>LQ (firms): ${lqTxt}</div><div>Firms: ${firmsTxt(rec.n_firms)}</div>`;
				} else if (lqBasis === 'jobs') {
					const jobsTxt = Number.isFinite(rec.total_jobs) ? Number(rec.total_jobs).toLocaleString() : 'N/A';
					rows = `<div>LQ (jobs): ${lqTxt}</div><div>Total jobs: ${jobsTxt}</div><div>Firms: ${firmsTxt(rec.n_firms)}</div>`;
				} else {
					const salesTxt = Number.isFinite(rec.sales) ? formatSales(rec.sales) : 'Suppressed / no data';
					rows = `<div>LQ (sales): ${lqTxt}</div><div>Sales: ${salesTxt}</div><div>Firms: ${firmsTxt(rec.n_firms)}</div>`;
				}

				if (popup) popup.remove();
				popup = new maplibregl.Popup({ closeButton: false, closeOnClick: false })
					.setLngLat(event.lngLat)
					.setHTML(`<div style="font-family:OpenSans,sans-serif;font-size:13px;line-height:1.6;background:#1e2433;color:#e0e0e0;padding:10px;border-radius:8px;">
						<div style="font-weight:600;margin-bottom:4px;color:#ffffff;">${name}</div>
						${rows}
					</div>`)
					.addTo(map);
			});

			map.on('mouseleave', FILL_LAYER, () => {
				hoveredUid = null;
				map.getCanvas().style.cursor = '';
				if (popup) { popup.remove(); popup = null; }
			});

			
		});

		map.on('style.load', () => { map.setProjection({ type: map.getZoom() < 7 ? 'globe' : 'mercator' }); });
		map.on('zoom', () => { map.setProjection({ type: map.getZoom() < 7 ? 'globe' : 'mercator' }); });
	});

	onDestroy(() => {
		if (popup) popup.remove();
		if (map) map.remove();
		popup = null; map = null;
	});
</script>

<div class="map-wrapper" class:light={!darkMode}>
	<div class="map" bind:this={mapContainer}></div>
	<div class="total-overlay"
		style="background:{darkMode ? '#1e2433' : '#ffffff'}; border-color:{darkMode ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.15)'};">
		<div class="total-label" style="color:{darkMode ? 'rgba(255,255,255,0.6)' : 'rgba(0,0,0,0.5)'};">{totalLabel}</div>
		<div class="total-value" style="color:{darkMode ? '#ffffff' : '#111111'};">{totalDisplay}</div>
	</div>
</div>

<div class="legend-bar">
	<div class="legend-inner">
		{#if colourType === 'totals'}
			<div class="legend-title">Total {lqBasis}</div>
			<div class="ramp-wrap">
				<div class="ramp" style="background: linear-gradient(to right, {SEQ_LO} 0%, {SEQ_HI} 100%)"></div>
				<div class="ticks">
					<span style="left:0%">{lqBasis === 'sales' ? formatSales(0) : '0'}</span>
					<span style="left:100%">{lqBasis === 'sales' ? formatSales(absClamp) : Math.round(absClamp).toLocaleString()}</span>
				</div>
			</div>
		{:else}
			<div class="legend-title">Location quotient ({lqBasis})</div>
			<div class="ramp-wrap">
				<div class="ramp" style="background: linear-gradient(to right, {UNDER} 0%, {MID} 50%, {OVER} 100%)"></div>
				<div class="ticks">
					<span style="left:0%">{(1/lqClamp).toFixed(2)}×</span>
					<span style="left:50%" class="tick-strong">1.0×</span>
					<span style="left:100%">{lqClamp.toFixed(1)}×</span>
				</div>
			</div>
			<div class="legend-note">1.0× = national average</div>
		{/if}
		<div class="legend-note"><span class="swatch-grey"></span> No data / suppressed</div>
	</div>
</div>

{#if showMilitaryBases}
<div class="legend-bar" style="margin-top: 4px;">
    <div class="legend-inner">
        <div class="legend-title">Military bases (CFB)</div>
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
	.total-overlay {
		position: absolute; top: 12px; left: 12px;
		border-radius: 6px; padding: 8px 12px; font-family: OpenSans; border: 1px solid;
	}
	.total-label { font-size: 11px; font-family: OpenSansBold; margin-bottom: 2px; }
	.total-value { font-size: 20px; font-family: TradeGothicBold; }
	.legend-bar {
		max-width: 1080px; width: 100%; margin: 8px auto 0; padding: 8px 12px;
		font-family: OpenSans; font-size: 12px; color: var(--brandWhite);
		display: flex; flex-direction: column; align-items: center;
	}
	.legend-title { font-family: OpenSansBold; margin-bottom: 6px; }
	.legend-note  { align-self: flex-start; }
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
	.ticks span.tick-strong { color: var(--brandWhite); }
	.ticks span.tick-strong::before {
		content: ''; position: absolute; bottom: 16px; left: 50%;
		width: 1px; height: 12px; background: var(--brandGray90);
	}

	/* Dark mode — invert the default white controls to dark */
	.map-wrapper :global(.maplibregl-ctrl-bottom-left .maplibregl-ctrl) { 
		filter: invert(1) brightness(0.7); 
	}
	/* Light mode — use controls as-is (they're already dark on white) */
	.map-wrapper.light :global(.maplibregl-ctrl-bottom-left .maplibregl-ctrl) { 
		filter: none; 
	}
	.map-wrapper {
		position: relative; width: 100%; max-width: 1080px; margin: 0 auto;
		height: 62vh; min-height: 460px; border: 1px solid rgba(255,255,255,0.1);
	}
	.map { width: 100%; height: 100%; }
	.swatch-grey { display: inline-block; width: 12px; height: 12px; background: #2a2a3a; border: 1px solid rgba(248,248,248,0.5); border-radius: 2px; }
	:global(.maplibregl-popup-content) {
		border-radius: 12px; background: transparent !important;
		padding: 0 !important; box-shadow: 0 4px 20px rgba(0,0,0,0.6) !important;
	}
	:global(.maplibregl-popup-close-button) { color: #ffffff; }
	:global(.maplibregl-ctrl-bottom-left) { margin: 16px; }
	@media (max-width: 720px) { .map-wrapper { height: 58vh; min-height: 380px; } }
</style>
